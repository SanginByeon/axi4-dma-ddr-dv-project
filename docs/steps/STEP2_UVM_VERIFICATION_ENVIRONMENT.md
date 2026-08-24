# Step 2 — UVM 기반 검증 환경 구축

## 개요

Step 1의 directed testbench를 Transaction, Sequence, Driver, Monitor, Scoreboard,
Agent, Environment 및 Test로 구성된 UVM 검증 환경으로 전환함.

Step 1의 정상 전송 4건을 동일한 주소와 크기로 재현하고, 각 source memory에
검증용 pattern을 주입하여 모든 전송 구간의 데이터 무결성을 확인함. DUT, DDR memory
model의 AXI4 동작 및 functional coverage model은 유지하고, DDR memory model의 기존
reset 기반 pattern 초기화 로직은 제거함.

## 목적

Stimulus 생성, DUT 구동, 동작 관측 및 결과 판정을 UVM component별로 분리하여 검증
환경의 재사용성과 확장성을 개선하기 위함.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `design.sv` | AXI4 interface, DMA controller 및 DDR memory model을 포함하는 compile entry |
| `axi4_if.sv` | AXI4 채널 신호와 master/slave modport 정의 |
| `dma_controller.sv` | AXI4 기반 메모리 복사를 수행하는 DUT |
| `ddr_memory_model.sv` | DUT의 AXI4 요청에 응답하는 검증용 메모리 모델 |
| `mmio_if.sv` | MMIO register 접근·interrupt 신호의 그룹화 및 TB/DUT modport 정의 |
| `coverage.sv` | 전송 크기·FSM 상태·주소 정렬·burst 길이·상태 전이 및 cross coverage 측정 |
| `testbench.sv` | DUT·interface 연결, virtual interface 전달 및 UVM test 실행 |
| `utility_pkg.sv` | MMIO 접근, DMA 완료 대기, source memory preload 및 DDR backdoor read 제공 |
| `dma_tx.sv` | DMA 설정값, constraint 및 source preload용 payload를 정의하는 sequence item |
| `dma_base_seq.sv` | DMA transaction 생성과 randomization을 위한 기본 sequence |
| `dma_s1_seq.sv` | 256B 기본 복사 sequence |
| `dma_s2_seq.sv` | 1024B 대용량 복사 sequence |
| `dma_s3_seq.sv` | 16B 및 64B 소형 복사 sequence |
| `dma_driver.sv` | Transaction을 MMIO stimulus로 변환하고 DMA 실행 결과 확인 |
| `dma_monitor.sv` | MMIO write와 interrupt를 관측하여 DMA transaction 복원 |
| `dma_scoreboard.sv` | Source/destination 메모리 데이터 비교 및 예상 transaction 수 일치 여부 확인 |
| `dma_agent.sv` | Monitor를 생성하고 Active mode에서 Sequencer·Driver 추가 및 연결 |
| `dma_env.sv` | Agent·Scoreboard 생성 및 analysis port 연결 |
| `dma_test.sv` | UVM environment 설정, sequence 실행, coverage 및 결과 보고 |

## 주요 변경 사항

- 개별 task로 구현된 테스트 시나리오를 UVM sequence와 transaction 기반 stimulus 구조로 재구축
- UVM phase system을 통한 검증 환경의 생성·연결, reset, stimulus 실행, 결과 확인 및
  report 절차 체계화
- `uvm_config_db`를 통해 MMIO/AXI4 virtual interface를 UVM component에 전달
- Active Agent 내부의 Sequencer·Driver 연결과 Monitor의 독립적인 transaction 관측 구성
- Driver가 모든 transaction의 `STATUS` 완료·오류 상태와 실제 전송 바이트 수를 확인하도록
  검증 절차 표준화
- DMA 설정값을 `dma_tx`로 추상화하고 4-byte 정렬, 4KB memory 범위 및 전송 영역 비중첩
  constraint 정의
- DDR memory model의 기존 reset 기반 pattern 초기화 로직을 제거하고, 각 시나리오 실행 전에
  `dma_tx`가 생성한 검증용 data pattern을 source memory에 backdoor로 preload하도록 memory
  초기화 책임을 UVM Sequence로 이전
- Monitor가 수집한 주소와 크기를 기준으로 source/destination 전체 전송 구간을 32-bit word
  단위로 비교하는 Scoreboard 구현
- Scoreboard에서 X/Z data를 검증 실패로 처리하고 예상·실제 transaction 수 일치 여부 확인
- `testbench.sv`와 `utility_pkg.sv`의 `$display` 기반 진행 로그를 `uvm_info`로 전환하여
  verbosity에 따라 출력하도록 구성
- `dma_test.sv`에서 UVM 계층의 verbosity를 일괄 설정하고 UVM report summary 제공

## 테스트 시나리오

Step 1의 정상 전송 4건을 동일한 순서로 실행함.

| 번호 | 시나리오 이름 |
|---:|---|
| S1 | 256B 기본 복사 (`0x0000` → `0x0400`) |
| S2 | 1024B 대용량 복사 (`0x0100` → `0x0800`) |
| S3-1 | 16B 소형 복사 (`0x0200` → `0x0300`) |
| S3-2 | 64B 소형 복사 (`0x0210` → `0x0310`) |

## VCS 실행 설정

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options: 없음
- 기본 설정에 `-debug_access+all`을 추가하여 `uvm_hdl_deposit()`과 `uvm_hdl_read()`가 DDR memory
  model에 backdoor로 접근할 수 있도록 설정함.

## VCS 검증 결과

| 항목 | Step 1 | Step 2 |
|---|---:|---:|
| 테스트 결과 | PASS | PASS |
| 정상 전송 | 4건 | 4건 |
| 데이터 비교 | S1 샘플 8 words 일치 | 4개 전송 전체 340 words 일치 |
| Transaction count 검사 | 미적용 | 예상 4건 / 확인 4건 |
| UVM Warning/Error/Fatal | 미적용 | 0 / 0 / 0 |
| 실행 시간 | 10175ns | 10415ns |
| 추정 throughput | 1069.29Mbps | 1044.65Mbps |
| Transfer size coverage | 75.00% | 75.00% |
| DMA state coverage | 85.71% | 85.71% |
| Address alignment coverage | 50.00% | 50.00% |
| Size/alignment cross | 42.86% | 42.86% |
| Overall functional coverage | 64.80% | 64.80% |

- Step 1 log: [`step1_simulation.log`](../../runs/step1_simulation.log)
- Step 2 log: [`step2_simulation.log`](../../runs/step2_simulation.log)

동일한 정상 전송 시나리오와 coverage 결과를 UVM 환경에서 재현하고, 데이터 비교 범위를
샘플 8 words에서 전체 340 words로 확장하여 검증 강도를 높였음을 확인함.

실행 시간과 추정 throughput의 차이는 UVM phase 및 추가 MMIO 확인 절차가 포함된 검증 환경의
실행 시간 차이이며, DUT 자체의 성능 변화로 해석하지 않음.
