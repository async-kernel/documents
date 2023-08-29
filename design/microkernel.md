# 基于用户态中断的微内核设计方案

用 Rust 实现一个微内核，负责功能只包括基本的虚存管理、TCB 管理、IPC。虚存管理等可能和架构相关，目前只考虑 RISC-V 。

**设计目标**：

- 实现 zero-copy ：IPC buffer 即为共享内存，无拷贝开销，用户态中断确保 client 和 server 的同步；
- 统一同步和异步接口：POSIX 标准都是同步接口，但 client 也可以使用异步接口；
- 兼容性：底层由 microkernel 提供基本的服务，上层 libos 提供接口运行应用（不需要对应用进行改动）；
- 隔离性：filesystem、device driver 和 app 通过地址空间进行隔离，且崩溃后不影响内核的运行；
- 同步互斥：尽量不在微内核内使用同步互斥机制，将此类问题交给用户态解决；
- 发挥 Rust 语言天然的优势，所有权机制、内存安全、无运行时 gc 。

**设计方案**：

IPC 设计为 client 和 server 模型：server 需要实现并向内核注册用户态中断处理函数；client 通过系统调用向 server 申请服务，内核会在 server 地址空间内开辟一块 IPC buffer 用于通信，并将该 IPC buffer 共享给 client，同时 client 注册为用户态中断的发送方。服务分为同步和异步两种，异步则申请服务时将 server 注册为 client 的发送方。

client 通过 POSIX 库函数的方式使用 server 提供的功能，并将 function call 转换为一次用户态中断支持的 IPC ，client 默认采用同步的方式等待结果，可以轮询并等待 server 向 IPC buffer 写入结果；如果 client 采用异步的方式，可以注册用户态中断处理函数，server 对异步请求进行处理后发送用户态中断通知。

为确保应用的兼容性，需要对系统调用进行分析，参数分为数值和指针两类，数值可以直接用 IPC buffer 传递，而指针情况比较复杂，有的指针是需要 server 填写返回值（read），有的则是 client 发送的数据（write）：

- openat：库函数根据文件路径查找 server 并申请服务，在文件描述符表中记录对应的 server ，IPC buffer 的地址，uipi index 等信息。 
- read/write：查找文件描述符表，向 IPC buffer 填写参数，等待 IPC buffer 的结果（可让权，也可轮询）。
- async read/write：先注册用户态中断处理函数（响应数据返回事件的回调函数）读取 IPC buffer 的结果，再完成类似于同步接口的操作，然后库函数直接返回。

微内核系统调用接口：

- **Register**：向 server 申请服务，例如 client 向 filesystem server ，filesystem 向 device driver
- **Unregister**：向 server 撤销服务，回收 IPC buffer ，清空用户态中断相关表项
- **Call**：lib 层采用混合策略，小数据直接读写 IPC buffer ，该接口只针对较大数据的情况，kernel 将 client 的 buffer 指针重映射给 server ，并将 IPC buffer 内的参数修改为 server 地址空间内的 buffer 指针。

利用页表的隔离机制，将一部分内核信息共享给 Task 地址空间（只读），包括当前每个核运行的 Task ID ，server 提供服务的 cap （server 注册用户态中断处理函数后生成 cap ，用于 Task 向 server 申请服务），内核信息按处理器核分页，避免读写冲突。

**device driver** 可以注册用户态中断处理函数处理外设中断和软件中断（IPC 使用软件中断），并根据 ucause 判断中断类型并分别进行处理。

**存在的问题**：

- 不同 client 向同一个 server 发请求的同步问题：用户态中断的 64 pending bits 可以区分优先级，同优先级 client 需要有先后的顺序，server 会记录某一位 pending bit 对应的已注册的 client，从而可以在中断到来时看其中哪些 client 发出了请求，内核会共享一块区域给所有 client ，库函数将里面的时间戳填入到请求中，这样 server 可以知道请求的先后顺序。
- 库函数执行的安全性问题：client 一般默认使用 POSIX 接口，Rust 语言是否可以在编译期对接口进行检查，防止 client 非法执行操作获取并篡改 lib 维护的信息，比如改上述的时间戳导致抢占其他 client 的请求。
- client 之间的通信：根据观察追求性能的应用一般不会搞很多跨地址空间的进程，而是采用多线程的方式。
- TOCTOU 或 Double Fetch：server 在接收到中断并完成 IPC buffer 的数据检查后，client 可能恶意修改 IPC buffer 内的数据，一种可能的解决办法是 server 先对数据进行一次拷贝，这样会引入一次拷贝开销；如果对大数据进行 remap 可能会造成 TLB shootdown ；共享数据如果连续在多个地址空间内进行传递，则必须从一个 shared buffer 拷贝到另一个。L4 采用的策略是 temporary mapping ，仍需要一次 caller 到 communication window 的拷贝开销。能否通过 Rust 语言的特性来解决这一问题？ 