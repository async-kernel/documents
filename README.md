---
title: AsyncOS
titleOnly: true
weight: 1
bookToc: false
---

# AsyncOS - 基于 Rust 协程异步机制的操作系统

阅读地址：<https://AsyncOS.github.io>

仓库地址：<https://github.com/AsyncOS/AsyncOS.github.io>

## 文档列表

- [异步操作系统设计方案](https://github.com/AsyncOS/AsyncOS.github.io/blob/main/content/design/overview.md)

## 添加/更新文档

在 `content/` 目录添加或者更新文档。

以下是一些 make 命令简化流程：

* `make new doc=design/hi.md`：从模板中创建 `content/design/hi.md` 文件
* `make serve`：本地预览文档
  * 如需修改地址和端口，使用 `make serve BIND=xxx PORT=xxx`
* `make generate`：在 public 目录中生成静态网页
  * 通常需要 baseURL 调整地址：`make generate baseURL=your-url`
