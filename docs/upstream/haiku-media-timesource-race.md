# Haiku bug report draft: use-after-free of BTimeSource in BMediaEventLooper

Draft for https://dev.haiku-os.org/newticket (component: Kits/Media Kit).

## Summary

A media node's `BMediaEventLooper` control thread can use its `BTimeSource`
after the node's message thread has released it in response to
`NODE_SET_TIMESOURCE`. The time source's cloned communication area is deleted,
and the control thread segfaults in `BTimeSource::GetTime()` reading `fBuf`.

## Observed

- hrev60368 (x86_64), real hardware (Ryzen 5 7600X). Seen with a .NET game
  using OpenAL (openal 1.21.1 from HaikuPorts), which plays through a Media Kit
  node. Intermittent: hit on launch after a reboot, twice in a row; went
  away after Preferences → Media → Restart media services.
- Crashing thread: `<app> control` (the node's `BMediaEventLooper`):

  ```
  BTimeSource::GetTime(long*, long*, float*) + 0x26    movl (%rcx), %eax   <- fBuf
  BTimeSource::RealTimeFor(long, long) + 0x3c
  BMediaEventLooper::ControlLoop() + 0x1be
  BMediaEventLooper::_ControlThreadStart(void*) + 0x1c
  ```

- `fBuf` (rcx) is non-NULL, but no area in the team covers that address, and
  there is no `__cloned_timesource_buf_*` area in the team at all.
- It happens during process teardown: in every run where the app's own log
  was available, the main thread had already died from an unhandled .NET
  exception, and the control thread then crashed this way while the process
  was exiting. So nodes being released or time sources being dropped at exit
  hit the same unprotected window. (The original trigger in those runs was an
  unrelated app bug, since fixed.)

## Analysis (current master)

- `fBuf` is only set by a successful `clone_area()` in
  `BTimeSource::BTimeSource(media_node_id)` (the kernel's `_user_clone_area`
  writes the address back only on success), so the area was mapped and later
  deleted.
- `BTimeSource::~BTimeSource()` deletes `fArea`.
- `BMediaNode::HandleMessage(NODE_SET_TIMESOURCE)` (MediaNode.cpp) calls
  `fTimeSource->RemoveMe(this); fTimeSource->Release(); fTimeSource = NULL;`
  and then creates the new time source, on the node's message thread.
- `BMediaEventLooper::ControlLoop()` calls `TimeSource()->RealTime()` /
  `TimeSource()->RealTimeFor(...)` on the control thread, with no lock or
  reference held against that swap.

So if the time source is switched while the control loop is running (for
example, a sound player node being moved onto the output's time source right
after it starts), the control thread can be inside `RealTimeFor()` on an
object whose area was just deleted. The faulting state above is exactly that.

- The same node thread also crashed in `BPrivate::SharedBufferList::Lock()`
  (from `SoundPlayNode::FillNextBuffer`) during exit, and after a normal
  quit from the app's menu, so the problem is broader than the time source:
  libmedia's state is torn down at exit while node threads still run.

## Suggested fix

Make the swap safe for the control thread, e.g. take a reference
(`Acquire()`) on the time source in `ControlLoop()` for the duration of each
use, or defer `Release()` of the old time source until the control loop has
switched over (protected by a lock shared with `TimeSource()`). Separately,
`BTimeSource::BTimeSource(media_node_id)` should set `fBuf = NULL` when
`clone_area()` fails, as `FinishCreate()` already does.

## Workaround used by applications

Avoiding the abnormal exit avoids it in practice; playing without the Media
Kit (OpenAL null output) avoids it entirely. Restarting the media services
appeared to help once, but that was likely coincidence.
