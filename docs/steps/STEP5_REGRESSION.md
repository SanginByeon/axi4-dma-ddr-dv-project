# Step 5 — Multi-Seed Backpressure Regression

## 개요

Step 4에서 기능 검증과 functional coverage closure를 완료한 DUT를 대상으로, AXI4 W 채널의
random backpressure 발생 timing을 변경하며 반복 검증함. Backpressure 확률 6종과 전송 크기
6종을 조합한 36개 transaction을 하나의 seed에서 실행하고, seed `1001`부터 `1010`까지
10회의 독립된 simulation을 수행함.

각 실행에서 Scoreboard가 source와 destination의 전체 전송 영역을 비교하고, AXI4 W 채널
A-01~A-03 assertion checker가 stall 중 payload와 WVALID 유지 및 WLAST timing을 확인하도록
구성함. 총 360개 transaction과 25,560 words의 data 비교를 완료했으며, 모든 seed에서
data mismatch, timeout, UVM error 및 assertion violation 없이 PASS를 확인함.

## 목적

서로 다른 seed로 생성한 다양한 backpressure timing과 반복 전송 조건에서도 DUT가 데이터
손실, timeout 또는 AXI4 protocol violation 없이 정상 동작하는지 확인하고, Step 3·4에서
발견하고 수정한 W payload, FIFO prefetch 및 WLAST 관련 오류의 재발 여부를 자동으로 검출할
수 있는 regression 체계를 구축하기 위함.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `design.sv` | AXI4·DDR model interface, DMA controller 및 DDR memory model을 포함하는 compile entry |
| `axi4_if.sv` | AXI4 채널 신호와 master/slave modport 정의 |
| `ddr_model_if.sv` | Backpressure 확률과 BRESP 오류 주입 설정을 DDR memory model에 전달 |
| `dma_controller.sv` | AXI4 기반 메모리 복사를 수행하는 DUT |
| `ddr_memory_model.sv` | AXI4 요청 응답 및 확률 기반 W 채널 backpressure 생성 |
| `mmio_if.sv` | MMIO register 접근·interrupt 신호의 그룹화 및 TB/DUT modport 정의 |
| `coverage.sv` | Step 4의 functional coverage model 보존; Step 5 판정에는 미사용 |
| `axi_checker.sv` | AXI4 W 채널 payload 유지, WVALID 유지 및 WLAST timing assertion 정의 |
| `testbench.sv` | DUT·검증 환경·checker 연결 및 `UVM_TESTNAME` 기반 test 선택 실행 |
| `utility_pkg.sv` | MMIO 접근, DMA 종료 대기, source preload 및 DDR backdoor read 제공 |
| `dma_tx.sv` | DMA 설정과 backpressure/error injection 조건을 정의하는 sequence item |
| `dma_base_seq.sv` | DMA transaction 생성과 randomization을 위한 기본 sequence |
| `dma_s1_boundary_seq.sv` | Step 4 정상 전송 크기와 burst/tail 경계 sequence |
| `dma_s2_size_error_seq.sv` | Step 4 size error sequence |
| `dma_s3_backpressure_seq.sv` | Step 4 burst 길이와 backpressure 강도 조합 sequence |
| `dma_s4_slverr_seq.sv` | Step 4 BRESP SLVERR 단독 주입 sequence |
| `dma_s5_backpressure_slverr_seq.sv` | Step 4 backpressure와 BRESP SLVERR 결합 sequence |
| `dma_s6_error_recovery_seq.sv` | Step 4 오류 이후 정상 전송 복구 sequence |
| `dma_s7_random_seq.sv` | Step 4 constrained-random 정상 전송 sequence |
| `dma_regression_seq.sv` | Seed별 backpressure 확률·전송 크기 matrix의 36개 transaction 생성 |
| `dma_driver.sv` | DDR model 조건 설정, MMIO stimulus 구동 및 DMA 실행 결과 확인 |
| `dma_monitor.sv` | MMIO write, backpressure 조건 및 완료 interrupt 관측 |
| `dma_scoreboard.sv` | Source/destination data 비교 및 예상 transaction 수 확인 |
| `dma_agent.sv` | Active mode의 Sequencer·Driver와 Monitor 구성 |
| `dma_env.sv` | Agent·Scoreboard 생성 및 analysis port 연결 |
| `dma_test.sv` | `UVM_TESTNAME` 미지정 시 실행되는 Step 4 종합 검증 test |
| `dma_regression_test.sv` | Seed 확인, regression sequence 실행 및 seed별 최종 결과 판정 |

## 주요 변경 사항

- `dma_regression_seq`와 `dma_regression_test`를 `dv/uvm/regression`에 분리하여 Step 4 기능
  검증 시나리오와 Step 5 반복 검증 구성을 구분
- `testbench.sv`가 `+UVM_TESTNAME=dma_regression_test`를 통해 regression test를 선택하고,
  option이 없으면 기존 `dma_test`를 실행하도록 구성
- `dma_regression_test`가 `+ntb_random_seed`의 numeric seed를 확인하고 sequence와 최종 결과
  report에 전달하도록 구성
- 하나의 seed에서 0%·10%·30%·50%·70%·90% backpressure와
  4B·16B·64B·80B·512B·1,028B 전송 크기를 조합한 36개 transaction 실행
- Scenario 이름에 seed, backpressure 확률 및 전송 크기를 기록하여 실패 조건의 추적과
  동일 seed 재실행을 지원
- 기존 Scoreboard의 전체 전송 영역 data 비교와 AXI4 W 채널 A-01~A-03 assertion checker를
  regression 판정에 편입
- Seed별 transaction `36/36`, UVM warning/error/fatal 0건 및 assertion violation 0건을
  종합하여 개별 simulation의 PASS/FAIL 판정
- Functional coverage는 Step 4에서 closure를 완료했으므로 재측정하지 않고, throughput 역시
  프로젝트의 기능·protocol 검증 범위를 벗어나므로 regression 판정에서 제외

상세 regression 계획은 [`REGRESSION_PLAN.md`](../REGRESSION_PLAN.md)에 정의함.

## Regression Matrix

| Backpressure 확률 | 전송 크기 | Seed 수 | Seed당 Transaction | 전체 Transaction |
|---:|---|---:|---:|---:|
| 0% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| 10% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| 30% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| 50% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| 70% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| 90% | 4B, 16B, 64B, 80B, 512B, 1,028B | 10 | 6 | 60 |
| **전체** | **6개 전송 크기** | **10** | **36** | **360** |

모든 transaction은 `src_addr=0x0000`, `dst_addr=0x0800`, `error_inject=0`으로 실행함.
최대 크기인 1,028B에서도 source 영역 `0x0000~0x0403`과 destination 영역
`0x0800~0x0C03`이 4 KB memory 안에서 중첩되지 않음.

Size error와 BRESP SLVERR는 입력 설정에 따라 결정적으로 실행되는 경로이며 Step 4의 directed
test와 functional coverage를 통해 검증을 완료함. Step 5는 매 cycle 난수에 따라 발생 시점이
달라지는 W 채널 backpressure에 범위를 한정함.

## VCS 실행 설정

Step 4와 동일한 VCS, UVM 및 compile option을 사용하고, Run options에서 regression test와
seed를 지정함.

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options 예시:

  ```text
  +UVM_TESTNAME=dma_regression_test +ntb_random_seed=1001
  ```

Seed를 `1001`부터 `1010`까지 변경하며 총 10회의 simulation을 수행함. 같은 seed와 동일한
코드로 재실행하면 해당 random backpressure 조건을 재현할 수 있음.

## VCS 검증 결과

| Seed | Transaction | Data 비교 | UVM Warning/Error/Fatal | A-01/A-02/A-03 | 실행 시간 | 결과 |
|---:|---:|---:|---:|---:|---:|---:|
| [1001](../../runs/regression/step5_seed_1001.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 138,155ns | PASS |
| [1002](../../runs/regression/step5_seed_1002.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 136,325ns | PASS |
| [1003](../../runs/regression/step5_seed_1003.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 138,325ns | PASS |
| [1004](../../runs/regression/step5_seed_1004.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 134,045ns | PASS |
| [1005](../../runs/regression/step5_seed_1005.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 136,075ns | PASS |
| [1006](../../runs/regression/step5_seed_1006.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 136,835ns | PASS |
| [1007](../../runs/regression/step5_seed_1007.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 138,065ns | PASS |
| [1008](../../runs/regression/step5_seed_1008.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 135,655ns | PASS |
| [1009](../../runs/regression/step5_seed_1009.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 135,825ns | PASS |
| [1010](../../runs/regression/step5_seed_1010.log) | 36/36 | 36건 PASS | 0/0/0 | 0/0/0 | 134,935ns | PASS |
| **전체** | **360/360** | **360건 PASS** | **0/0/0** | **0/0/0** | **1,364,240ns** | **PASS** |

10개 seed에서 실행한 360개 transaction과 전체 25,560 words의 source/destination data가
모두 일치함. DMA timeout과 UVM warning/error/fatal이 발생하지 않았으며, A-01~A-03
assertion violation도 모두 0건으로 확인됨.

동일한 36개 transaction을 실행했지만 seed별 완료 시간이 134,045ns~138,325ns로 서로
다르게 측정됨. 이는 seed에 따라 DDR memory model의 random stall 발생 순서가 달라졌음을
보여주며, 검증한 다양한 stall timing에서 데이터 무결성과 AXI4 W 채널의 assertion 검증
항목이 정상적으로 유지됨을 확인함.

Functional coverage는 Step 4에서 100% closure를 완료했으므로 Step 5 결과에 포함하지 않음.
모든 seed가 PASS하여 별도 failure 재현 log나 디버깅 파형은 생성하지 않음.
