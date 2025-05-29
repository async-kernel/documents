---
title: 用户态中断扩展应用方案
weight: 3
---

# 用户态中断扩展应用方案

## （异步）中断 / Interrupt

由于时钟中断和跨核的软件中断总是在 M 态产生，而 M 态的程序通常无法获知用户态程序的信息，故先将 M 态的中断转发至 S 态，再由内核判断是在内核中处理还是转发至用户进程；对于由用户进程处理的中断，若当前核上正在运行的恰为目标进程，则可立刻将 `uip` 寄存器中相应的位设置为 1 （可能还需清除 `sie` 和 `sip` 中的相关位），在 `SRET` 指令之后 CPU 将自动跳转到 `utvec` 寄存器指示的中断处理程序中；否则，将中断信息暂存入进程控制块中的待处理中断队列，当目标进程即将被调度运行时，如果队列非空，则将队列信息复制到用户地址空间（或直接将该队列存储在用户地址空间而非内核空间），队列的地址写入 `uscratch` 或者 `utval` 寄存器，设置 `uip` 和 `sie` 进行中断注入。如果要求进程尽可能早地对中断作出响应，可以在插入中断信息后，暂时性提高目标进程的优先级，使其更早地被调度执行。

对于外部中断，使用上述方法仍然是可行的，但目前的规范允许 PLIC 直接产生用户态的外部中断，如何利用这一点实现一种更高效的方案有待讨论。

### 时钟中断

在 RISC-V 特权级规范中，对于时钟中断有如下描述：

> A machine timer interrupt becomes pending whenever `mtime` contains a value greater than or equal to `mtimecmp`, treating the values as unsigned integers.
> Lower privilege levels do not have their own `timecmp` registers. Instead, machine-mode software can implement any number of virtual timers on a hart by multiplexing the next timer interrupt into the `mtimecmp` register.

硬件总是产生 M 态的时钟中断，当 M 态没有使用时钟中断的需求时，可以在 M 态的中断处理程序中无条件转发时钟中断到 S 态（置位 `mip.STIP` 并清除 `mie.MTIE` ）；在 S 态维护一个计时器队列（实际可能实现为一个红黑树），记录到期时刻和请求源（内核或某个进程），队列按照到期时刻由早到晚排序。

设置定时器时，若请求的时刻早于队列中所有时刻，则（通过 SBI call ）将其写入 `mtimecmp` 。接收到时钟中断时，将 `mtimecmp` 与队列中的到期时刻进行比较，判断该中断的请求源，同时丢弃比该请求更早的所有请求。若请求源为某个进程，则按照前述方法进行中断注入。

通过上述方法实现虚拟定时器后，可以更好地支持用户态线程调度器、[可抢占函数调用](https://www.usenix.org/conference/atc20/presentation/boucher)等功能。

### 软件中断

RISC-V 规范中对于软件中断有如下描述：

> Interprocessor interrupts at supervisor level are implemented through implementation-specific mechanisms, e.g., via calls to an SEE, which might ultimately result in a machine-mode write to the receiving hart’s MSIP bit.
> We allow a hart to directly write only its own SSIP bit, not those of other harts, as other harts might be virtualized and possibly descheduled by higher privilege levels. We rely on calls to the SEE to provide interprocessor interrupts for this reason. Machine-mode harts are not virtualized and can directly interrupt other harts by setting their MSIP bits, typically using uncached I/O writes to memory-mapped control registers depending on the platform specification.

跨核软中断需要通过 SBI call ，由 SBI 经 CLINT 置位目标核上的 `mip.MSIP` 位，而程序只能写入本核的 `mip.SSIP` 位，因为 S 态程序可能运行在虚拟核上；出于同样的理由，我们应当限制程序只能写入本核的 `mip.USIP` 位。

当队列中有多个待处理的中断时，可以约定在调度时由内核注入一个软件中断，而各个中断的具体信息从队列中获得。

### 外部中断

外部中断可能用来实现用户态的硬件驱动；实现方案待讨论。

## （同步）异常 / Exception

可能用来支持浮点异常、除零异常的处理，以及捕获程序本身抛出的异常。
