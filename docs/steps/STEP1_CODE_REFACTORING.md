# Step 1 — 코드 구조 분리

## 개요

Baseline의 `design.sv`와 `testbench.sv`에 혼재되어 있던 설계·검증 구성요소를 역할별 파일로
분리함.

DUT, directed test scenario 및 functional coverage model의 동작은 변경하지 않음. Utility
task의 event control, 신호 구동 순서 및 MMIO 접근 timing 유지.

## 목적

Baseline의 통합 설계·검증 코드를 역할별 파일로 분리하여 구성요소의 책임과 의존 관계를
명확히 하고, 기존 검증 동작을 유지하면서 Step 2의 UVM 환경 전환을 위한 구조적 기반을
마련하기 위함.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `design.sv` | AXI4 interface, DMA controller 및 DDR memory model을 포함하는 compile entry |
| `axi4_if.sv` | AXI4 채널 신호와 master/slave modport 정의 |
| `dma_controller.sv` | AXI4 기반 메모리 복사를 수행하는 DUT |
| `ddr_memory_model.sv` | DUT의 AXI4 요청에 응답하는 검증용 메모리 모델 |
| `mmio_if.sv` | MMIO register 접근·interrupt 신호의 그룹화 및 TB/DUT modport 정의 |
| `utility_pkg.sv` | 재진입 가능한 MMIO read/write, DMA 완료 대기 및 status polling task 제공 |
| `coverage.sv` | 전송 크기·FSM 상태·주소 정렬·burst 길이·상태 전이 및 cross coverage 측정 |
| `testbench.sv` | Clock/reset 생성, 검증 환경 연결, directed scenario 실행 및 결과 보고 |

## 주요 변경 사항

- Baseline `design.sv`의 AXI4 interface, DMA controller 및 DDR memory model을 역할별 파일로 분리
- EDA Playground에서 이름을 변경할 수 없는 기본 Design 파일인 `design.sv`를 compile entry로 유지하고,
  분리된 AXI4 interface, DMA controller 및 DDR memory model을 `include`하도록 구성
- DDR 메모리 모델의 모듈 이름을 실제 역할에 맞게 `ddr_controller`에서 `ddr_memory_model`로 변경
- MMIO 신호의 interface 분리 및 `tb_mp`, `dut_mp` modport 정의
- MMIO read/write 및 DMA 완료 대기 task의 package 분리와 `automatic` 선언
- Baseline covergroup의 별도 파일 분리
- `testbench.sv`의 검증 환경 연결 및 scenario 실행 역할 중심 단순화

## 테스트 시나리오

Baseline의 directed scenario를 동일한 순서로 실행함.

| 번호 | 시나리오 이름 |
|---:|---|
| S1 | 256B 기본 복사 |
| S2 | 1024B 대용량 |
| S3 | 16B/64B |

## VCS 검증 결과

| 항목 | Baseline | Step 1 |
|---|---:|---:|
| 테스트 결과 | PASS | PASS |
| 데이터 비교 | 샘플 8 words 일치 | 샘플 8 words 일치 |
| 실행 시간 | 10175ns | 10175ns |
| 추정 throughput | 1069.29Mbps | 1069.29Mbps |
| Transfer size coverage | 75.00% | 75.00% |
| DMA state coverage | 85.71% | 85.71% |
| Address alignment coverage | 50.00% | 50.00% |
| Size/alignment cross | 42.86% | 42.86% |
| Overall functional coverage | 64.80% | 64.80% |

- Baseline log: [`baseline_simulation.log`](../../baseline/baseline_simulation.log)
- Step 1 log: [`step1_simulation.log`](../../runs/step1_simulation.log)

Baseline과 동일한 기능·성능·coverage 결과 재현을 통해 파일 분리가 검증 동작에 영향을 주지 않았음을 확인함.
