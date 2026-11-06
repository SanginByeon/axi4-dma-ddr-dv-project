# AXI4 기반 DMA–DDR 메모리 모델 시스템 검증 고도화 프로젝트

> 🌐 **English Version:** View the fully translated project at **[axi4-dma-ddr-dv-project-ENG](https://github.com/SanginByeon/axi4-dma-ddr-dv-project-ENG)**.

교육과정에서 제공된 AXI4 DMA–DDR baseline 코드를 기준으로 설계 구조를 분리하고, UVM 기반
검증 환경, random backpressure와 오류 주입, functional coverage, assertion checker 및
multi-seed regression을 단계적으로 구축한 개인 프로젝트입니다.

최종적으로 Step 4의 세 functional coverage group에서 100% closure를 달성하고, Step 5의
10개 seed·360개 transaction regression에서 25,560 words의 data 일치와 AXI4 W assertion
violation 0건을 확인했습니다.

## 프로젝트 범위와 코드 출처

[`baseline/design.sv`](baseline/design.sv)와
[`baseline/testbench.sv`](baseline/testbench.sv)는 교육과정에서 제공된 코드를 수정하지 않은
기준점으로 보존했습니다.

- 코드 출처:
[패스트캠퍼스, 삼코치의 반도체 실무 로드맵: 설계 · 검증 · Layout · AI반도체](https://fastcampus.co.kr/data_online_samcoach2)

본 프로젝트의 작업 범위는 다음과 같습니다.

- `design.sv`에 함께 정의된 AXI4 interface, DMA controller 및 DDR memory model을 역할별 파일로 분리
- 개별 task 기반 testbench를 UVM sequence와 transaction 기반 검증 환경으로 재구축
- 검증용 DDR memory model에 AXI4 W 채널 random backpressure와 BRESP SLVERR 주입 기능 추가
- Source/destination data 무결성, X/Z 및 transaction count를 판정하는 Scoreboard 구축
- Transaction·DMA FSM·AXI event 기반 functional coverage model 고도화
- AXI4 W 채널 protocol 검증을 위한 SVA 기반 assertion checker 구현
- Backpressure·오류 응답·coverage 분석 과정에서 발견한 DUT 버그의 원인 분석 및 수정
- Functional Coverage closure와 10개 seed 기반 regression 수행
- 검증 계획, 디버깅 과정, 파형 및 단계별 simulation 결과 문서화

Baseline 시스템의 구조와 동작은
[`BASELINE_SYSTEM_ANALYSIS.md`](baseline/BASELINE_SYSTEM_ANALYSIS.md)에 정리했습니다.

## 시스템 및 검증 구조

DMA controller는 MMIO로 설정한 source 주소, destination 주소 및 전송 크기를 사용하여 AXI4
read/write transaction으로 데이터를 복사합니다. DDR memory model은 DUT 검증을 위한 AXI4
Slave이며, 4 KB memory와 제어 가능한 W 채널 backpressure 및 BRESP 오류 응답을 제공합니다.

### 시스템 구조

```text
                  dma_test / dma_regression_test
                                │
                                ▼
                Sequence ─► Sequencer
                                │
                                ▼
                              Driver
                                │
              ┌─────────────────┴────────────────┐
              │                                  │
              │ mmio_if                          │ ddr_model_if
              │ SRC/DST/SIZE/CTRL 설정            │ Backpressure/SLVERR 설정
              ▼                                  ▼
     ┌────────────────────┐       AXI4        ┌─────────────────────┐
     │ DMA Controller     │ ◄───────────────► │ DDR Memory Model    │
     │       DUT          │    AR/R/AW/W/B    │ 4 KB mem[]          │
     └─────────┬──────────┘                   └─┬────────┬──────────┘
               │                                │        ▲
               │ mmio_if           ddr_model_if │        │
               │                                │        │
               ├────────────────────────────────┘        │
               │                                         │
               ▼                                         │
            Monitor ◄── mmio_if / ddr_model_if 관측       │
               │        SRC/DST/SIZE/CTRL                │
               │        done/error interrupt             │
               │        Backpressure/SLVERR              │
               │                                         │
               │ 수집한 DMA transaction                    │
               ▼                                         │
           Scoreboard ─────── backdoor read ─────────────┘
               │
               └─ Source data와 destination data 비교

     AXI4 W signals ─────────► SVA Assertion Checker
     Transaction/FSM/AXI ────► Functional Coverage
```

### 검증 흐름

```text
[1] Test 선택
    dma_test
      └─ Step 4의 S1~S7 기능 검증 실행

    dma_regression_test
      └─ Step 5의 seed별 36개 backpressure transaction 실행
                           │
                           ▼
[2] Transaction 생성
    Sequence가 SRC / DST / SIZE / CTRL / backpressure 조건 생성
                           │
                           ├─ data_payload pattern 생성
                           └─ utility_pkg를 통해 source memory preload
                           │
                           ▼
[3] DUT 및 DDR Memory Model 설정
    Sequencer → Driver
              ├─ mmio_if로 DMA의 SRC / DST / SIZE / CTRL register 설정
              └─ ddr_model_if로 backpressure 확률 / error injection 설정
                           │
                           ▼
[4] DMA 전송
    DMA Controller
       ├─ AXI4 AR/R   : source memory read
       ├─ FIFO        : read data buffering
       └─ AXI4 AW/W/B : destination memory write 및 response 확인
                           │
                           ▼
[5] DDR Memory Model 응답
    DDR Memory Model
       ├─ 설정 확률에 따라 WREADY random 비활성화
       ├─ 정상 write data를 mem[]에 저장
       └─ 설정에 따라 BRESP OKAY 또는 SLVERR 반환
                           │
                           ▼
[6] 완료 관측
    DMA Controller
       ├─ 정상 완료 → dma_done_int
       └─ 오류 발생 → dma_error_int

    Monitor가 MMIO 설정과 interrupt를 기반으로 transaction 재구성
                           │
                           ▼
[7] 데이터 무결성 판정
    Monitor → Scoreboard
              ├─ source address의 data backdoor read      : expected
              ├─ destination address의 data backdoor read : actual
              ├─ expected와 actual을 전체 전송 영역에서 비교
              ├─ X/Z data 검출
              └─ 예상/수집 transaction count 비교
                           │
                           ▼
[8] 병렬 검증
    SVA Assertion Checker
       └─ W payload / WVALID / WLAST protocol 조건 검사

    Functional Coverage
       └─ Transaction / DMA FSM / AXI event 측정
                           │
                           ▼
[9] 최종 판정
    UVM error / warning / fatal
    + Scoreboard transaction count
    + AXI assertion violation
    + Functional coverage 또는 regression 결과
                           │
                           ▼
                      PASS / FAIL
```

## 검증 고도화 과정

| 단계 | 주요 내용 | 결과 | 문서 |
|---|---|---|---|
| Baseline | 교육과정 제공 코드와 초기 결과 보존 | Functional coverage 64.80% | [시스템 분석](baseline/BASELINE_SYSTEM_ANALYSIS.md) |
| Step 1 | Design·interface·testbench 역할별 코드 분리 | Baseline 동작과 coverage 재현 | [코드 구조 분리](docs/steps/STEP1_CODE_REFACTORING.md) |
| Step 2 | UVM Driver·Monitor·Scoreboard·Agent·Environment 구축 | 4 transaction, 340 words 일치 | [UVM 환경 구축](docs/steps/STEP2_UVM_VERIFICATION_ENVIRONMENT.md) |
| Step 3 | Random WREADY backpressure와 BRESP SLVERR 주입 | DUT 문제 재현·수정, 전체 340 words 일치 | [Backpressure·오류 주입](docs/steps/STEP3_BACKPRESSURE_ERROR_INJECTION.md) |
| Step 4 | 7개 시나리오 기반 기능 검증, coverage model 고도화와 assertion checker 구현 | 37/37 transaction, 세 covergroup 100% | [시나리오 확장·Coverage Closure](docs/steps/STEP4_SCENARIO_EXPANSION_AND_COVERAGE_CLOSURE.md) |
| Step 5 | 10개 seed 기반 backpressure regression | 360/360 transaction, 25,560 words 일치 | [Multi-Seed Regression](docs/steps/STEP5_REGRESSION.md) |

Baseline과 Step 3까지의 coverage와 Step 4 coverage는 서로 다른 coverage model을 사용하므로
수치 자체를 직접 비교하지 않습니다. Step 4에서는 검증 계획에 따라 재구축한 reachable
coverpoint와 cross의 100% 달성을 closure 기준으로 사용했습니다.

## 주요 검증 항목

- 1·4·16-beat burst와 multi-burst/tail 전송의 데이터 무결성
- 4-byte 미만 및 4-byte 비배수 전송 크기의 `error_code=0x2` 처리
- Low·medium·high W 채널 backpressure에서 handshake와 payload 안정성
- BRESP SLVERR의 `error_code=0x3`, error interrupt 및 오류 이후 정상 전송 복구
- Source/destination memory region과 비중첩 주소 constraint
- DMA FSM 상태·전이, transaction 조건 및 실제 AXI event functional coverage
- Stall 중 W payload 유지, WVALID 유지 및 마지막 beat WLAST timing assertion
- 서로 다른 10개 seed에서 random stall timing에 대한 반복 검증

검증 계획과 구현 항목은 다음 문서에 정의했습니다.

| 문서 | 내용 |
|---|---|
| [Verification Plan](docs/VERIFICATION_PLAN.md) | 검증 목표, 대상, 범위 및 결과 판정 기준 |
| [Test Plan](docs/TEST_PLAN.md) | S1~S7 sequence별 transaction matrix |
| [Coverage Plan](docs/COVERAGE_PLAN.md) | Coverpoint·cross 정의와 coverage 목표 |
| [Assertion Set](docs/ASSERTION_SET.md) | AXI4 W 채널 A-01~A-03 assertion 정의 |
| [Regression Plan](docs/REGRESSION_PLAN.md) | Seed·backpressure·전송 크기 matrix와 판정 기준 |

## DUT 디버깅 사례

| 사례 | 관측 현상 | 원인 및 수정 | 상세 문서 |
|---|---|---|---|
| W 채널 data mismatch | Backpressure 적용 시 source와 destination 불일치 | DUT가 WVALID만으로 payload를 갱신하던 조건을 handshake 기준으로 수정하고 불필요한 FIFO prefetch 제거 | [W 채널 Data Mismatch](docs/debug/AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md) |
| BRESP 오류 상태 전이 | SLVERR 응답 후 `S_ERROR` 대신 `S_DONE` 진입 | 갱신 전 `stat.error` 참조를 제거하고 현재 BRESP handshake에서 응답을 직접 판정 | [BRESP 오류 경로](docs/debug/AXI4_BRESP_ERROR_PATH_DEBUGGING.md) |
| WLAST timing | 4-beat burst의 마지막 data 이후 WLAST 활성화 | WLAST 생성 기준을 현재 beat가 아닌 다음 handshake beat로 수정 | [WLAST 타이밍](docs/debug/AXI4_WLAST_TIMING_DEBUGGING.md) |

각 사례는 문제 재현 log, 수정 전·후 파형, 원인 코드와 재검증 결과를 함께 보존했습니다.

## 최종 검증 결과

| 항목 | 결과 |
|---|---:|
| Step 4 sequence / transaction | 7개 / 37건 |
| Step 4 expected / actual UVM error | 20 / 20건 |
| Transaction coverage | 100.00% |
| DMA FSM coverage | 100.00% |
| AXI event coverage | 100.00% |
| AXI4 W assertion violation | 0건 |
| Regression seed | 10/10 PASS |
| Regression transaction | 360/360 PASS |
| Regression data 비교 | 25,560 words 일치 |
| Regression UVM warning/error/fatal | 0/0/0 |

Step 4의 UVM error 20건은 size error와 SLVERR negative test에서 예상한 보고이며, 예상값과
실제값이 일치해 최종 PASS로 판정했습니다. Step 5는 정상 backpressure 전송만 반복하므로
UVM error 없이 모든 seed가 PASS했습니다.

- Step 4 결과: [`step4_simulation.log`](runs/step4_simulation.log)
- Step 5 결과: [`runs/regression`](runs/regression)

## 실행 방법

### 환경

- Simulator: Synopsys VCS 2025.06
- Verification methodology: UVM 1.2
- Target environment: EDA Playground

EDA Playground에서는 [`design.sv`](design.sv)와 [`dv/testbench.sv`](dv/testbench.sv)를 compile
entry로 사용하고, 저장소의 include source를 각각 추가합니다.

Compile options:

```text
-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
```

Step 4 종합 검증은 Run options 없이 실행합니다. `testbench.sv`는 `UVM_TESTNAME`이 없으면
기본적으로 `dma_test`를 실행합니다.

Step 5 regression은 seed별로 다음 Run options를 사용합니다.

```text
+UVM_TESTNAME=dma_regression_test +ntb_random_seed=1001
```

Seed를 `1001`부터 `1010`까지 변경하여 총 10회 실행하며, 결과는
[`runs/regression`](runs/regression)에 seed별 log로 보존했습니다.

## 저장소 구조

```text
.
├── .gitattributes
├── README.md
├── design.sv
│
├── baseline/                              # 교육과정 제공 원본, 시스템 분석 및 초기 실행 결과
│   ├── design.sv
│   ├── testbench.sv
│   ├── BASELINE_SYSTEM_ANALYSIS.md
│   └── baseline_simulation.log
│
├── rtl/                                   # DMA controller DUT
│   └── dma_controller.sv
│
├── interface/                             # AXI4, MMIO 및 DDR memory model 제어 interface
│   ├── axi4_if.sv
│   ├── mmio_if.sv
│   └── ddr_model_if.sv
│
├── dv/                                    # DDR model, coverage, testbench 및 UVM 검증 환경
│   ├── coverage.sv
│   ├── ddr_memory_model.sv
│   ├── testbench.sv
│   ├── utility_pkg.sv
│   │
│   ├── checkers/                          # AXI4 W 채널 SVA checker
│   │   └── axi_checker.sv
│   │
│   └── uvm/                               # Transaction과 UVM component·test
│       ├── dma_tx.sv
│       ├── dma_driver.sv
│       ├── dma_monitor.sv
│       ├── dma_scoreboard.sv
│       ├── dma_agent.sv
│       ├── dma_env.sv
│       ├── dma_test.sv
│       │
│       ├── sequences/                     # Step 4 기능 검증 sequence
│       │   ├── dma_base_seq.sv
│       │   ├── dma_s1_boundary_seq.sv
│       │   ├── dma_s2_size_error_seq.sv
│       │   ├── dma_s3_backpressure_seq.sv
│       │   ├── dma_s4_slverr_seq.sv
│       │   ├── dma_s5_backpressure_slverr_seq.sv
│       │   ├── dma_s6_error_recovery_seq.sv
│       │   └── dma_s7_random_seq.sv
│       │
│       └── regression/                    # Step 5 multi-seed regression 구성
│           ├── dma_regression_seq.sv
│           └── dma_regression_test.sv
│
├── docs/                                  # 검증·test·coverage·assertion·regression 문서
│   ├── VERIFICATION_PLAN.md
│   ├── TEST_PLAN.md
│   ├── COVERAGE_PLAN.md
│   ├── ASSERTION_SET.md
│   ├── REGRESSION_PLAN.md
│   │
│   ├── steps/                             # 프로젝트 수행 단계별 변경 내용과 실행 결과
│   │   ├── STEP1_CODE_REFACTORING.md
│   │   ├── STEP2_UVM_VERIFICATION_ENVIRONMENT.md
│   │   ├── STEP3_BACKPRESSURE_ERROR_INJECTION.md
│   │   ├── STEP4_SCENARIO_EXPANSION_AND_COVERAGE_CLOSURE.md
│   │   └── STEP5_REGRESSION.md
│   │
│   ├── debug/                             # DUT 버그의 재현·원인·수정·재검증 기록
│   │   ├── AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md
│   │   ├── AXI4_BRESP_ERROR_PATH_DEBUGGING.md
│   │   └── AXI4_WLAST_TIMING_DEBUGGING.md
│   │
│   └── images/                            # 디버깅 근거 파형
│       ├── step3/                         # W payload·FIFO prefetch·BRESP 디버깅 파형
│       │   ├── axi_w_payload_stability_violation.png
│       │   ├── axi_w_payload_fixed.png
│       │   ├── axi_w_payload_prefetch_fixed.png
│       │   ├── bresp_error_path_failure.png
│       │   └── bresp_error_path_fixed.png
│       └── step4/                         # WLAST timing 디버깅 파형
│           ├── wlast_timing_failure.png
│           └── wlast_timing_fixed.png
│
└── runs/                                  # 프로젝트 수행 단계별 VCS 실행 log
    ├── step1_simulation.log
    ├── step2_simulation.log
    ├── step3_simulation.log
    ├── step4_simulation.log
    │
    ├── debug/                             # DUT 버그와 coverage gap 재현 log
    │   ├── step3_w_payload_failure.log
    │   ├── step3_bresp_error_path_failure.log
    │   └── step4_wlast_coverage_gap.log
    │
    └── regression/                        # Step 5 regression 결과 log
        ├── step5_seed_1001.log
        ├── step5_seed_1002.log
        ├── step5_seed_1003.log
        ├── step5_seed_1004.log
        ├── step5_seed_1005.log
        ├── step5_seed_1006.log
        ├── step5_seed_1007.log
        ├── step5_seed_1008.log
        ├── step5_seed_1009.log
        └── step5_seed_1010.log
```

## 검증 범위와 제한 사항

- Baseline DDR memory model은 4 KB memory로 구현되어 있으며, 검증 주소 범위도 이를 기준으로 제한했습니다.
- DUT가 지원하는 4-byte aligned, 32-bit word 단위 전송을 중심으로 검증했습니다.
- Random backpressure는 AXI4 W 채널에 적용하고, 오류 주입은 BRESP SLVERR로 한정했습니다.
- A-01~A-03은 프로젝트에서 중점적으로 분석한 W 채널 protocol 항목을 검사하며, 전체 AXI4
  protocol compliance를 의미하지 않습니다.
- Functional coverage 100%는 본 프로젝트에서 정의한 reachable coverpoint와 cross의 closure를
  의미하며 모든 입력 조합의 완전 탐색을 의미하지 않습니다.
- Simulation log의 기존 throughput 계산은 실제 transaction 구성을 반영하지 않으므로 성능
  결과로 사용하지 않았으며, throughput 측정은 프로젝트 범위에서 제외했습니다.
