#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

#define STANDARD_SM_SUPPORTED
#define RVMODEL_DATA_SECTION
#define RVMODEL_BOOT

#define RVMODEL_ACCESS_FAULT_ADDRESS 0x40000000

#define RVMODEL_HALT_PASS       \
  li t0, 0x100000fc           ;\
  li t1, 1                    ;\
1: sw t1, 0(t0)               ;\
  j 1b

#define RVMODEL_HALT_FAIL       \
  li t0, 0x100000fc           ;\
  li t1, 3                    ;\
1: sw t1, 0(t0)               ;\
  j 1b

#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

#endif

