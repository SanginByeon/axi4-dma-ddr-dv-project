# DMA Test Plan

## 1. 개요

본 문서는 Step 4에서 실행하는 7개 sequence와 총 37개 transaction의 stimulus 값을 정의한다.
검증 목표와 결과 판정 구조는 [`VERIFICATION_PLAN.md`](./VERIFICATION_PLAN.md), coverage 목표는
[`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md), assertion 항목은
[`ASSERTION_SET.md`](./ASSERTION_SET.md)에 정의한다.

## 2. 공통 설정

- 모든 transaction은 `enable=1`, `start=1`, `irq=1`을 사용한다.
- Source와 destination 주소는 4-byte aligned, 4 KB memory 범위 및 비중첩 조건을 만족한다.
- Source memory는 각 transaction 실행 전에 `32'hCAFE_0000 + word index` pattern으로 초기화한다.
- `backpressure_prob`은 DDR memory model이 WREADY를 비활성화할 확률이다.
- `error_inject=1`이면 write burst 완료 후 DDR memory model이 `BRESP=SLVERR`를 반환한다.
- Size error와 SLVERR는 의도적인 negative-test 결과이며 예상 UVM error 수에 포함한다.

## 3. 시나리오 요약

| ID | Sequence | Transaction 수 | 목적 | 예상 UVM error |
|---|---|---:|---|---:|
| S1 | [`dma_s1_boundary_seq.sv`](../dv/uvm/sequences/dma_s1_boundary_seq.sv) | 11 | 정상 전송 크기와 burst/tail 경계 확인 | 0 |
| S2 | [`dma_s2_size_error_seq.sv`](../dv/uvm/sequences/dma_s2_size_error_seq.sv) | 4 | 4-byte 미만 및 비배수 size error 확인 | 12 |
| S3 | [`dma_s3_backpressure_seq.sv`](../dv/uvm/sequences/dma_s3_backpressure_seq.sv) | 9 | Burst 길이와 backpressure 강도 조합 확인 | 0 |
| S4 | [`dma_s4_slverr_seq.sv`](../dv/uvm/sequences/dma_s4_slverr_seq.sv) | 1 | Backpressure 없는 BRESP SLVERR 확인 | 1 |
| S5 | [`dma_s5_backpressure_slverr_seq.sv`](../dv/uvm/sequences/dma_s5_backpressure_slverr_seq.sv) | 3 | Backpressure와 BRESP SLVERR 결합 확인 | 3 |
| S6 | [`dma_s6_error_recovery_seq.sv`](../dv/uvm/sequences/dma_s6_error_recovery_seq.sv) | 4 | Size error·SLVERR 이후 정상 복구 확인 | 4 |
| S7 | [`dma_s7_random_seq.sv`](../dv/uvm/sequences/dma_s7_random_seq.sv) | 5 | Constraint 기반 정상 전송 추가 확인 | 0 |
| 합계 |  | **37** |  | **20** |

## 4. Directed Test Matrix

### 4.1 S1: 정상 전송 경계값

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S1-1 | 4 | `0x0000` | `0x0400` | 0% | 0 | 정상 완료, data 일치 |
| S1-2 | 12 | `0x0400` | `0x0C00` | 0% | 0 | 정상 완료, 1-beat 반복 |
| S1-3 | 16 | `0x0C00` | `0x0000` | 0% | 0 | 정상 완료, 4-beat burst |
| S1-4 | 60 | `0x0100` | `0x0500` | 0% | 0 | 정상 완료, 4-beat burst와 1-beat tail |
| S1-5 | 64 | `0x0500` | `0x0C00` | 0% | 0 | 정상 완료, 16-beat burst |
| S1-6 | 68 | `0x0C00` | `0x0000` | 0% | 0 | 정상 완료, 16-beat burst와 1-beat tail |
| S1-7 | 80 | `0x0200` | `0x0600` | 0% | 0 | 정상 완료, 16-beat와 4-beat burst |
| S1-8 | 256 | `0x0600` | `0x0C00` | 0% | 0 | 정상 완료, multi-burst |
| S1-9 | 1,024 | `0x0000` | `0x0800` | 0% | 0 | 정상 완료, multi-burst |
| S1-10 | 1,028 | `0x0000` | `0x0800` | 0% | 0 | 정상 완료, multi-burst와 1-beat tail |
| S1-11 | 2,048 | `0x0000` | `0x0800` | 0% | 0 | 정상 완료, 최대 비중첩 전송 |

### 4.2 S2: Size error

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S2-1 | 1 | `0x0080` | `0x0380` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-2 | 2 | `0x0480` | `0x0C80` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-3 | 3 | `0x0C40` | `0x0040` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-4 | 15 | `0x0180` | `0x0680` | 0% | 0 | 12B 처리 후 잔여 3B에서 `error_code=0x2` |

### 4.3 S3: W channel backpressure

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S3-1 | 4 | `0x0100` | `0x0500` | 10% | 0 | 정상 완료, data 일치 |
| S3-2 | 16 | `0x0500` | `0x0C00` | 10% | 0 | 정상 완료, data 일치 |
| S3-3 | 64 | `0x0C00` | `0x0100` | 10% | 0 | 정상 완료, data 일치 |
| S3-4 | 4 | `0x0100` | `0x0500` | 50% | 0 | 정상 완료, data 일치 |
| S3-5 | 16 | `0x0500` | `0x0C00` | 50% | 0 | 정상 완료, data 일치 |
| S3-6 | 64 | `0x0C00` | `0x0100` | 50% | 0 | 정상 완료, data 일치 |
| S3-7 | 4 | `0x0100` | `0x0500` | 90% | 0 | 정상 완료, data 일치 |
| S3-8 | 16 | `0x0500` | `0x0C00` | 90% | 0 | 정상 완료, data 일치 |
| S3-9 | 64 | `0x0C00` | `0x0100` | 90% | 0 | 정상 완료, data 일치 |

### 4.4 S4: BRESP SLVERR

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S4-1 | 64 | `0x0200` | `0x0A00` | 0% | 1 | `error_code=0x3`, error interrupt, data 일치 |

### 4.5 S5: Backpressure와 SLVERR 결합

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S5-1 | 4 | `0x0300` | `0x0700` | 10% | 1 | `error_code=0x3`, error interrupt, data 일치 |
| S5-2 | 16 | `0x0700` | `0x0C00` | 50% | 1 | `error_code=0x3`, error interrupt, data 일치 |
| S5-3 | 64 | `0x0C00` | `0x0300` | 90% | 1 | `error_code=0x3`, error interrupt, data 일치 |

### 4.6 S6: 오류 복구

| Test ID | Size (B) | Source | Destination | Backpressure | Error inject | 기대 결과 |
|---|---:|---:|---:|---:|---:|---|
| S6-1 | 3 | `0x0100` | `0x0900` | 0% | 0 | Size error, `error_code=0x2` |
| S6-2 | 16 | `0x0200` | `0x0A00` | 0% | 0 | Size error 이후 정상 완료 |
| S6-3 | 64 | `0x0300` | `0x0B00` | 0% | 1 | SLVERR, `error_code=0x3` |
| S6-4 | 16 | `0x0400` | `0x0C00` | 0% | 0 | SLVERR 이후 정상 완료 |

## 5. Constrained-Random Test Matrix

S7은 동일한 constraint를 적용해 5개 transaction을 생성한다. Directed test가 주요 경계값과
coverage 조합을 담당하므로, S7은 constrained-random 생성과 무작위 정상 전송을 추가 확인하는
보완 test로 사용한다. 5건은 통계적 random regression이나 coverage closure의 충분성을
주장하기 위한 반복 횟수가 아니다.

아래 값은 실행 전에 고정되지 않으며 실제 생성값은 simulation log의 S7 transaction에 기록한다.

| Test ID | Size | Source/Destination | Backpressure | Error inject | 기대 결과 |
|---|---|---|---|---:|---|
| S7-1~S7-5 | 4~256B, 4-byte 배수 | 4-byte 정렬, 4 KB 내부, 비중첩 | 1~99% | 0 | 정상 완료, data 일치 |

Source와 destination 시작 주소는 low/mid/high memory region에 분산되도록 가중치를 적용하고,
backpressure는 low(1~30%), medium(31~70%), high(71~99%) 구간에 동일한 가중치를 적용한다.

## 6. 예상 UVM Error

현재 Driver와 Scoreboard의 negative-test 보고 방식을 유지하므로 의도적인 오류 transaction도
`UVM_ERROR`를 발생시킨다.

| 오류 조건 | Transaction | Transaction당 UVM error | 합계 |
|---|---|---:|---:|
| Size error | S2-1~S2-4, S6-1 | Driver 1 + Scoreboard 2 | 15 |
| BRESP SLVERR | S4-1, S5-1~S5-3, S6-3 | Driver 1 | 5 |
| 합계 | 10개 negative transaction |  | **20** |

Step 4의 고정 test matrix에서는 `EXPECTED_UVM_ERROR_COUNT=20`으로 설정한다. 시나리오 수나
negative-test 보고 방식이 변경되면 예상값도 함께 갱신해야 한다.

## 7. 최종 판정 기준

- 예상/실제 UVM error 수 20건 일치
- UVM warning 및 fatal 0건
- 생성·검사 transaction 37건 일치
- AXI4 W channel assertion violation 0건
- Transaction, FSM 및 AXI event covergroup 각각 100% 달성

모든 조건을 만족하면 `dma_test`의 report phase에서 `FINAL TEST RESULT: PASSED`를 출력한다.
하나라도 충족하지 못하면 `FINAL TEST RESULT: FAILED`로 판정한다.
