# RISC-V N: 用户态中断

> version: 2021-05-18

## CSR

### `ustatus`

```
UXLEN    5   4    3  1    0
┌────────┬──────┬──────┬─────┐
│  WPRI  │ UPIE │ WPRI │ UIE │
└────────┴──────┴──────┴─────┘
UXLEN-5     1       3     1
```

`ustatus` 是一个 UXLEN 位长的读写寄存器，记录和控制硬件的工作状态。

用户态中断使能位 UIE 为零时阻止用户态中断的发生。UIE 中的值在用户态中断被处理时复制到 UPIE，并被置为零以为用户态陷入处理程序提供原子性。

UIE 和 UPIE 是 `mstatus` 和 `sstatus` 相同位的镜像。硬件实现中可以是同一寄存器。

指令 URET 用于从陷入返回用户态。URET 将 UPIE 复制回 UIE，然后设置 UPIE，最后将 `uepc` 拷贝至 `pc`。

用户态中断只能在用户态触发，所以不需要 UPP 等位。

### `uip` `uie`

```
| WPRI | UEIP | WPRI | UTIP | WPRI | USIP |

| WPRI | UEIE | WPRI | UTIE | WPRI | USIE |
```

定义三种中断：软件中断、时钟中断、外部中断。用户态软件中断通过置位当前的 hart 的 `uip` 的 USIP 来触发。通过清零该位来取消软件中断。当 `uie` 中的 USIE 为零时，用户态软件中断被禁止

ABI 应该提供一种机制来发送处理器间中断到其他 hart，这将最终导致接收 hart 的 `uip` 寄存器的 USIP 位被设置。

除了 USIP，其他位用户态只可读。

如果 `uip` 寄存器中的 UTIP 位被设置，一个用户级的定时器中断将被挂起。当 `uie` 寄存器中的 UTIE 位被清除时，用户级定时器中断被禁用。ABI 应该提供一个机制来清除一个待定的定时器中断。

如果 `uip` 寄存器中的 UEIP 位被设置，一个用户级的外部中断将被挂起。当 `uie` 寄存器中的 UEIE 位被清除时，用户级外部中断被禁用。ABI 应该提供屏蔽、解除屏蔽和查询外部中断原因的设施。

`uip` 和 `uie` 寄存器是 `mip` 和 `mie` 寄存器的子集。读取 `uip`/`uie` 的任何字段，或者写入任何可写字段，都会对 `mip`/`mie` 的同名字段进行读取或写入。如果实现了 S 模式，`uip` 和 `uie` 寄存器也是 `sip` 和 `sie` 寄存器的子集。

### `sedeleg` `sideleg`

为提升中断和异常的处理性能，可以实现独立的读写寄存器 `sedeleg` 和 `sideleg`，设置其中的位将特定的中断和异常交由用户态陷入处理程序处理。

当一个陷入被委托给一个权限较低的模式 u 时，`ucause` 寄存器被写入陷阱的原因；`uepc` 寄存器被写入发生陷阱的指令的虚拟地址；`utval` 寄存器被写入一个特定的异常数据；`mstatus` 的 UPIE 字段被写入陷阱发生时 UIE 字段的值；`mstatus` 的 UIE 字段被清零。`mcause`/`scause` 和 `mepc`/`sepc` 寄存器以及 `mstatus` 的 MPP 和 MPIE 字段不被写入。

一个实现不应硬性规定任何委托位为一，也就是说，任何可以被委托的陷阱都必须支持不被委托。一个实现方案是选择可委托的陷入的子集。支持的可委托位可通过向每个比特位置写 1，然后读回 `medeleg`/`sedeleg` 或 `mideleg`/`sideleg` 中的值，看看哪些位上有 1。

> 目前，不支持触发低权限级的陷入

不会在用户态发生的应硬件恒零，如 ECall from S/H/M-mode

### `uscratch`

`uscratch` 寄存器是一个 UXLEN 位读/写寄存器。

### `uepc`

`uepc` 是 UXLEN 位读写寄存器。最低位（`uepc[0]`）恒零。次低位 `uepc[1]` 视实现的对齐需求而定。

`uepc` 是 WARL 寄存器，应能存储所有的合法物理/虚拟地址，但不需要能挣钱存储非法地址。实现可以先将非法地址转为其他非法地址再写入 `uepc`。

但陷入在用户态处理时，`uepc` 被写入中断或触发异常的指令的虚拟地址。此外，除了软件显式地写，否则 `uepc` 应永不被写。

### `ucause`

```
| Interrupt | Exception Code WLRL |
```

`ucause` 是 UXLEN 位长读写寄存器。

### `utvec`

```
| BASE[UXLEN-1 : 2] | MODE |
```

`utvec` 是 UXLEN 位长读写寄存器，存储陷入向量，包括向量基地址和向量模式。

BASE 是 WARL，可以存储任意合法的虚拟地址或物理地址，需要 4 字节对齐。特殊的模式可以有其他对齐标准。

| value | name     | description       |
| ----- | -------- | ----------------- |
| 0     | direct   | base              |
| 1     | vectored | base + 4 \* cause |
|       |          | reserved          |

### `utval`

存储内容待讨论

## N 扩展指令

### `URET`
