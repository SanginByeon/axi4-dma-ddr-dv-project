# Step 3 — AXI4 W 채널 Backpressure 및 BRESP Error Injection 환경 구축

## 개요

Step 2의 UVM 검증 환경에 AXI4 W 채널 backpressure와 BRESP error injection 기능을
추가함. DDR memory model이 transaction별 설정에 따라 `WREADY`를 확률적으로
비활성화하거나 write response로 `SLVERR`를 반환하도록 구성함.

기존 정상 전송을 기준 시나리오로 유지하면서 10%·90% backpressure 조건과 BRESP
오류 주입 조건을 적용함. Backpressure 및 오류 응답 환경에서 발견한 DUT의 W payload,
FIFO prefetch 및 BRESP 상태 전이 버그를 수정하고 전체 전송 영역의 데이터 무결성과
오류 처리 경로를 재검증함.

## 목적

AXI4 Slave의 응답 지연과 오류 응답을 제어할 수 있는 검증 환경을 구축하여, 이상적인
응답 조건에서는 드러나지 않던 DUT의 protocol 처리 및 오류 상태 전이 문제를 재현하고
분석·수정할 수 있는 기반을 마련하기 위함.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `design.sv` | AXI4·DDR model interface, DMA controller 및 DDR memory model을 포함하는 compile entry |
| `axi4_if.sv` | AXI4 채널 신호와 master/slave modport 정의 |
| `ddr_model_if.sv` | Backpressure 확률과 BRESP 오류 주입 설정을 DDR memory model에 전달 |
| `dma_controller.sv` | AXI4 기반 메모리 복사를 수행하는 DUT |
| `ddr_memory_model.sv` | AXI4 요청 응답, W 채널 backpressure 및 BRESP SLVERR 생성 |
| `mmio_if.sv` | MMIO register 접근·interrupt 신호의 그룹화 및 TB/DUT modport 정의 |
| `coverage.sv` | 전송 크기·FSM 상태·주소 정렬·burst 길이·상태 전이 및 cross coverage 측정 |
| `testbench.sv` | DUT·interface 연결, virtual interface 전달 및 UVM test 실행 |
| `utility_pkg.sv` | MMIO 접근, 정상·오류 종료 대기, source preload 및 DDR backdoor read 제공 |
| `dma_tx.sv` | DMA 설정과 backpressure/error injection 조건을 정의하는 sequence item |
| `dma_base_seq.sv` | DMA transaction 생성과 randomization을 위한 기본 sequence |
| `dma_s1_seq.sv` | Backpressure와 오류 주입이 없는 256B 기준 복사 sequence |
| `dma_s2_seq.sv` | 10% backpressure가 적용된 1024B multi-burst sequence |
| `dma_s3_seq.sv` | 90% backpressure 및 BRESP SLVERR 주입 sequence |
| `dma_driver.sv` | DDR model 조건 설정, MMIO stimulus 구동 및 DMA 실행 결과 확인 |
| `dma_monitor.sv` | MMIO write, DDR model 조건 및 완료·오류 interrupt 관측 |
| `dma_scoreboard.sv` | Source/destination 데이터 비교 및 예상 transaction 수 확인 |
| `dma_agent.sv` | Monitor를 생성하고 Active mode에서 Sequencer·Driver 추가 및 연결 |
| `dma_env.sv` | Agent·Scoreboard 생성 및 analysis port 연결 |
| `dma_test.sv` | 기준·backpressure·오류 주입 sequence 실행 및 결과 보고 |

## 주요 변경 사항

- `ddr_model_if`를 추가하여 UVM Driver가 DDR memory model의 `backpressure_prob`와
  `error_inject` 조건을 transaction별로 설정하도록 구성
- DDR memory model이 AW handshake에서 검증 조건을 latch하고, write burst가 진행되는
  동안 설정된 확률에 따라 `WREADY`를 비활성화하도록 W 채널 backpressure 구현
- DDR memory model이 write burst 완료 후 latch된 `error_inject` 값에 따라
  `BRESP=SLVERR`를 반환하도록 오류 응답 주입 기능 구현
- `dma_tx`에 backpressure 확률과 오류 주입 필드를 추가하고, 기본값과 0~99% 범위
  constraint 정의
- Driver가 전송 크기와 backpressure 확률을 반영하여 timeout 여유를 계산하고,
  transaction 종료 후 DDR memory model 설정을 기본값으로 복구하도록 구성
- Monitor가 DMA 시작 시 적용된 backpressure와 error injection 조건을 transaction에 수집
- STATUS polling이 `done` 또는 `error`를 DMA 동작 종료 상태로 인식하도록 수정
- Backpressure 환경에서 발견한 W payload 갱신 조건 및 FIFO prefetch 범위 버그 수정
- BRESP SLVERR 주입으로 발견한 오류 상태 전이 조건 버그 수정

## DUT 디버깅

### AXI4 W 채널 Data Mismatch

Backpressure로 `WREADY=0`인 구간에도 DUT가 `WVALID`만 확인하여 다음 `WDATA`를
출력하면서 data mismatch가 발생함. Handshake가 성립할 때만 다음 W payload를
출력하도록 수정하고, 후속 data가 없는 경우의 불필요한 FIFO prefetch도 제거함.

- 상세 분석: [`AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md`](../debug/AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md)
- 문제 재현 log: [`step3_w_payload_failure.log`](../../runs/debug/step3_w_payload_failure.log)

### BRESP 오류 상태 전이

DUT가 `BRESP=SLVERR`를 감지해 `stat.error`를 설정했지만, next-state 조합 논리가
갱신 전 `stat.error`를 참조하여 `S_ERROR`가 아닌 `S_DONE`으로 전이함. 현재 handshake의
`BRESP`를 직접 확인하여 오류 상태를 결정하도록 수정함.

- 상세 분석: [`AXI4_BRESP_ERROR_PATH_DEBUGGING.md`](../debug/AXI4_BRESP_ERROR_PATH_DEBUGGING.md)
- 문제 재현 log: [`step3_bresp_error_path_failure.log`](../../runs/debug/step3_bresp_error_path_failure.log)

## 테스트 시나리오

| 번호 | 전송 크기 | Backpressure | Error injection | 검증 내용 |
|---:|---:|---:|---:|---|
| S1 | 256B | 0% | 비활성 | Step 2 기준 전송 재현 |
| S2 | 1024B | 10% | 비활성 | Multi-burst 환경의 W 채널 handshake 및 데이터 무결성 |
| S3-1 | 16B | 90% | 비활성 | 강한 backpressure 환경의 소형 burst 처리 |
| S3-2 | 64B | 0% | `BRESP=SLVERR` | Write response 오류 상태와 error interrupt |

## VCS 실행 설정

Step 2와 동일한 VCS, UVM 및 compile option을 사용함.

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options: 없음

## VCS 검증 결과

| 항목 | Step 2 | Step 3 |
|---|---:|---:|
| 시나리오 결과 | 정상 전송 4건 PASS | 정상 전송 3건 PASS, SLVERR 오류 경로 1건 확인 |
| 데이터 비교 | 4개 전송 전체 340 words 일치 | 4개 전송 전체 340 words 일치 |
| Transaction count | 예상 4건 / 확인 4건 | 예상 4건 / 확인 4건 |
| UVM Warning/Error/Fatal | 0 / 0 / 0 | 0 / 1 / 0 |
| 실행 시간 | 10415ns | 11005ns |
| 추정 throughput | 1044.65Mbps | 988.64Mbps |
| Transfer size coverage | 75.00% | 75.00% |
| DMA state coverage | 85.71% | 100.00% |
| Address alignment coverage | 50.00% | 50.00% |
| Size/alignment cross | 42.86% | 42.86% |
| Overall functional coverage | 64.80% | 66.84% |

- Step 2 log: [`step2_simulation.log`](../../runs/step2_simulation.log)
- Step 3 log: [`step3_simulation.log`](../../runs/step3_simulation.log)

S1, S2 및 S3-1은 Driver의 정상 완료 판정과 Scoreboard 데이터 비교를 통과함. S3-2는
의도적으로 주입한 SLVERR에 따라 `S_WR_RESP → S_ERROR`, `error_code=0x3` 및 error
interrupt 발생을 확인함. 모든 시나리오에서 source와 destination data가 일치했으며,
오류 상태 진입을 포함해 DMA state coverage가 100%로 증가함.

UVM summary의 error 1건은 Driver가 S3-2의 의도적인 `STATUS.error=1`을 보고한 결과임.
현재 단계에서는 오류 응답 경로의 동작을 확인하는 데 목적을 두며, error code에 대한
functional coverage와 오류 시나리오별 기대 결과 판정은 이후 coverage 고도화 단계에서
확장함.
