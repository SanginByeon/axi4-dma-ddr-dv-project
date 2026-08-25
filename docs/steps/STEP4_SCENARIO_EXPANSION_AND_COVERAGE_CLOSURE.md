# Step 4 — 테스트 시나리오 확장 및 Coverage Closure 기반 종합 검증

## 개요

Step 3의 검증 환경을 기반으로 정상 경계값, size error, backpressure, SLVERR,
오류 복구 및 constrained-random 조건으로 테스트 시나리오를 확장함. 7개 sequence에서
총 37개 transaction을 실행하고, 데이터 무결성, 오류 처리와 복구 및 AXI4 W 채널
protocol 준수 여부를 검증함.

검증 계획의 수행 여부를 측정하기 위해 coverage를 transaction, DMA FSM 및 AXI event의
세 covergroup으로 분리함. 확장한 시나리오의 기능 검증 결과와 coverage 결과를 함께
분석하여 검증 항목의 충족 여부를 확인함.

Coverage closure 과정에서 `cp_wlast_awlen`의 미도달 bin을 분석하여 DUT의 WLAST 생성
타이밍 버그를 발견하고 수정함. AXI4 W 채널 assertion과 최종 판정 기준을 추가한 뒤 모든
coverpoint와 cross의 100% 달성, assertion violation 0건 및 전체 테스트 PASS를 확인함.

## 목적

다양한 정상·오류·backpressure 조건으로 테스트 시나리오를 확장하여 데이터 무결성,
오류 처리와 복구 및 AXI4 W 채널 protocol을 검증하고, 수행 결과를 functional coverage로
측정하여 미도달 항목의 분석·보완과 coverage closure까지 완료하기 위함.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `design.sv` | AXI4·DDR model interface, DMA controller 및 DDR memory model을 포함하는 compile entry |
| `axi4_if.sv` | AXI4 채널 신호와 master/slave modport 정의 |
| `ddr_model_if.sv` | Backpressure 확률과 BRESP 오류 주입 설정을 DDR memory model에 전달 |
| `dma_controller.sv` | AXI4 기반 메모리 복사를 수행하는 DUT |
| `ddr_memory_model.sv` | AXI4 요청 응답, W 채널 backpressure 및 BRESP SLVERR 생성 |
| `mmio_if.sv` | MMIO register 접근·interrupt 신호의 그룹화 및 TB/DUT modport 정의 |
| `coverage.sv` | Transaction, DMA FSM 및 AXI event functional coverage model 정의 |
| `axi_checker.sv` | AXI4 W 채널 payload 유지, WVALID 유지 및 WLAST timing assertion 정의 |
| `testbench.sv` | DUT·검증 환경·checker 연결, virtual interface 전달 및 UVM test 실행 |
| `utility_pkg.sv` | MMIO 접근, 정상·오류 종료 대기, source preload 및 DDR backdoor read 제공 |
| `dma_tx.sv` | DMA 설정, backpressure/error injection 조건 및 constrained-random constraint 정의 |
| `dma_base_seq.sv` | DMA transaction 생성과 randomization을 위한 기본 sequence |
| `dma_s1_boundary_seq.sv` | 정상 전송 크기와 burst/tail 경계 sequence |
| `dma_s2_size_error_seq.sv` | 4-byte 미만 및 비배수 size error sequence |
| `dma_s3_backpressure_seq.sv` | Burst 길이와 backpressure 강도 조합 sequence |
| `dma_s4_slverr_seq.sv` | BRESP SLVERR 단독 주입 sequence |
| `dma_s5_backpressure_slverr_seq.sv` | Backpressure와 BRESP SLVERR 결합 sequence |
| `dma_s6_error_recovery_seq.sv` | Size error·SLVERR 이후 정상 전송 복구 sequence |
| `dma_s7_random_seq.sv` | 정상 전송 조건의 5건 constrained-random sequence |
| `dma_driver.sv` | DDR model 조건 설정, MMIO stimulus 구동 및 DMA 실행 결과 확인 |
| `dma_monitor.sv` | MMIO write, DDR model 조건 및 완료·오류 interrupt 관측 |
| `dma_scoreboard.sv` | Source/destination data 비교 및 예상 transaction 수 확인 |
| `dma_agent.sv` | Active mode의 Sequencer·Driver와 Monitor 구성 |
| `dma_env.sv` | Agent·Scoreboard 생성 및 analysis port 연결 |
| `dma_test.sv` | 7개 sequence 실행, checker·coverage report 및 최종 결과 판정 |

## 주요 변경 사항

- Verification Plan, Coverage Plan, Test Plan 및 Assertion Set을 분리하여 검증 목표와 구현
  항목의 추적성 확보
- 정상 경계값, size error, backpressure, SLVERR, 오류 복구 및 constrained-random 조건을 7개
  sequence와 37개 transaction으로 확장
- 기존 UVM component 구조를 유지하면서 Scoreboard의 source/destination data 비교, Driver의
  종료 상태 확인 및 오류 후 후속 transaction 실행을 통해 시나리오별 예상 동작 검증
- 매 cycle을 동일하게 sampling하던 기존 단일 covergroup을 transaction, DMA FSM 및 AXI event
  기준의 세 covergroup으로 재구축
- DUT의 크기 분기, burst/tail 처리, memory region, backpressure 강도, 오류 코드 및 실제 AXI
  handshake를 측정하는 19개 coverpoint와 5개 cross 정의
- AXI4 W 채널의 stall 중 payload 안정성, WVALID 유지 및 마지막 beat의 WLAST timing을 확인하는
  A-01~A-03 assertion checker 추가
- Negative test에서 발생하는 예상 UVM error 20건과 실제 error 수를 비교하고, transaction 수,
  checker violation 및 coverage closure를 종합한 최종 PASS/FAIL 판정 구성
- 모든 coverpoint와 cross의 개별 coverage를 ID와 함께 출력하도록 coverage report 확장
- UVM verbosity를 `UVM_MEDIUM`으로 조정하고 DUT 내부 진행 로그를 기본 비활성화하여 출력량 제어

상세 계획은 다음 문서에 정의함.

- 검증 계획: [`VERIFICATION_PLAN.md`](../VERIFICATION_PLAN.md)
- Coverage 계획: [`COVERAGE_PLAN.md`](../COVERAGE_PLAN.md)
- 테스트 계획: [`TEST_PLAN.md`](../TEST_PLAN.md)
- Assertion 항목: [`ASSERTION_SET.md`](../ASSERTION_SET.md)

## DUT 디버깅

### AXI4 W 채널 WLAST 타이밍

최초 실행에서 transaction coverage와 DMA FSM coverage는 100%를 달성했지만,
`cp_wlast_awlen`이 33.33%에 머물러 AXI event coverage가 92.59%로 확인됨. `cp_awlen`은
1·4·16-beat burst를 모두 측정했으므로 시나리오 누락이 아닌 WLAST 동작 문제로 판단하고
4-beat write burst 파형을 분석함.

DUT가 다음 `WDATA`를 출력하면서 현재 beat 번호로 WLAST를 계산하여, 마지막 data
handshake 이후에 WLAST가 활성화되는 문제를 확인함. WLAST를 다음 beat 번호인
`w_beats_sent + 1`을 기준으로 계산하도록 수정함.

- 상세 분석: [`AXI4_WLAST_TIMING_DEBUGGING.md`](../debug/AXI4_WLAST_TIMING_DEBUGGING.md)
- Coverage gap 재현 log:
  [`step4_wlast_coverage_gap.log`](../../runs/debug/step4_wlast_coverage_gap.log)

## 테스트 시나리오

| 번호 | Transaction 수 | 시나리오 | 검증 내용 |
|---:|---:|---|---|
| S1 | 11 | 정상 전송 경계값 | 크기, burst 및 tail 경계 처리 |
| S2 | 4 | Size error | 4-byte 미만 및 비배수 크기의 `error_code=0x2` |
| S3 | 9 | W 채널 backpressure | 1·4·16-beat burst와 10%·50%·90% backpressure 조합 |
| S4 | 1 | BRESP SLVERR | Backpressure 없는 `error_code=0x3` 경로 |
| S5 | 3 | Backpressure + SLVERR | Backpressure 강도별 BRESP 오류 처리 |
| S6 | 4 | 오류 복구 | Size error·SLVERR 직후 정상 전송 복구 |
| S7 | 5 | Constrained random | Constraint 기반 정상 전송 조합과 data 일치 추가 확인 |
| **합계** | **37** |  |  |

S1~S6의 directed test가 주요 경계값과 coverage 조합을 담당함. S7의 5건은 constraint에
따른 무작위 정상 전송 생성과 data 무결성을 추가 확인하기 위한 보완 test이며, 통계적
random regression이나 coverage closure의 주된 수단으로 사용하지 않음.

각 transaction의 주소, 크기, backpressure 및 예상 결과는
[`TEST_PLAN.md`](../TEST_PLAN.md)에 정의함.

## VCS 실행 설정

Step 2·3과 동일한 VCS, UVM 및 compile option을 사용함.

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options: 없음

## VCS 검증 결과

| 항목 | Step 3 | Step 4 |
|---|---:|---:|
| 실행 시나리오 | 4개 transaction | 7개 sequence, 37개 transaction |
| 정상/Size error/SLVERR | 3 / 0 / 1건 | 27 / 5 / 5건 |
| Transaction count | 예상 4건 / 확인 4건 | 예상 37건 / 확인 37건 |
| Data 비교 | 전체 340 words 일치 | 정상·SLVERR 32건 PASS, Size error 5건 예상 mismatch |
| UVM Warning/Error/Fatal | 0 / 1 / 0 | 0 / 20 / 0 |
| 예상/실제 UVM error | 미적용 | 20 / 20건 |
| AXI4 W assertion | 미적용 | A-01~A-03 violation 0건 |
| 실행 시간 | 11005ns | 56315ns |
| Transaction coverage | 미적용 | 100.00% |
| DMA FSM coverage | 미적용 | 100.00% |
| AXI event coverage | 미적용 | 100.00% |
| Overall functional coverage | 66.84% | 100.00% |
| 최종 판정 | PASS | PASS |

- Step 3 log: [`step3_simulation.log`](../../runs/step3_simulation.log)
- Step 4 log: [`step4_simulation.log`](../../runs/step4_simulation.log)

Step 4의 UVM error 20건은 5개의 size error transaction에서 발생한 Driver·Scoreboard
보고 15건과 5개의 SLVERR transaction에서 발생한 Driver 보고 5건으로, test plan에 정의한
예상 negative-test 결과임. 예상/실제 error 수 일치, warning·fatal 0건, transaction
37/37건 확인, AXI4 W assertion violation 0건 및 세 covergroup 100%를 모두 충족하여 최종
테스트를 PASS로 판정함.

실행 시간 증가는 시나리오가 4개 transaction에서 37개 transaction으로 확장된 결과이며,
DUT 자체의 성능 변화로 해석하지 않음.

Simulation log의 `Estimated throughput`은 기존 `analyze_performance()`가 Step 2·3의 전송량인
1,360B(`256+1024+16+64`)를 고정값으로 사용하는 계산 결과임. Step 4는 37개 transaction으로
전송 구성이 변경되었으므로 log에 출력된 throughput은 Step 4의 실제 처리량을 나타내지 않음.
정확한 측정을 위해서는 transaction별 실제 전송 byte와 DUT의 유효 전송 구간을 별도로
누적해야 하지만, throughput 측정과 성능 평가는 본 프로젝트의 기능·protocol 검증 범위를
벗어나므로 기존 계산 로직을 수정하지 않고 검증 결과 및 성능 비교에서 제외함.

Step 3과 Step 4의 overall coverage는 서로 다른 coverage model을 사용하므로 단순한 수치
증가로 비교하지 않으며, Step 4에서는 새로 정의한 reachable coverpoint와 cross의 100%
달성을 coverage closure 기준으로 사용함.
