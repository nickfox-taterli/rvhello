# ACT4 接入

这里保存 rvhello 的 ACT4 UDB 配置,链接脚本和 DUT 宏.测试集合本身不复制进仓库.

在 `riscv-arch-test` 根目录生成 RV32IM/Zicsr/Zifencei/Zicntr 自检 ELF:

```sh
CONFIG_FILES=/home/taterli/rvhello/sim/act4/test_config.yaml \
EXTENSIONS=I,M,Zicsr,Zifencei,Zicntr make -j$(nproc)
```

ACT4 当前还要求与 UDB 参数一致的 `sail.json`.该文件和 Sail 版本绑定,应使用当前
ACT4/UDB 工具从 `rvhello.yaml` 生成或按其同版本示例配置,不要在 RTL 仓库里固定旧版
Sail schema.生成 ELF 后回到本仓库执行:

```sh
make arch-test ACT_ELF_DIR=/path/to/riscv-arch-test/work/rvhello-rv32im/elfs
```

`arch-test` 会逐个把 ELF 转成字格式镜像,送入 `tb_arch`,并通过 `0x100000fc` 的
pass/fail 写事务收集结果.单个测试默认最多运行 2000000 个时钟周期.

