# AXI4 기반 DMA–DDR 메모리 모델 Baseline 시스템 분석

## 1. 개요

본 문서는 `design.sv`와 `testbench.sv`로 구성된 baseline 시스템의 구조와 동작을 정리한다.

### 시스템 요약

이 시스템은 AXI4 Master인 DUT `dma_controller`와 AXI4 Slave인 검증용 메모리 모델
`ddr_controller`를 연결한 메모리 복사 환경이다. Testbench는 MMIO로 DUT를 설정하고 전송
상태와 결과를 확인한다.

### 코드 출처

- 패스트캠퍼스, 삼코치의 반도체 실무 로드맵: 설계 · 검증 · Layout · AI반도체
- <https://fastcampus.co.kr/data_online_samcoach2>

### 용어

검증 환경의 `ddr_controller`는 실제 DDR 제어 로직이나 PHY가 아니라 **DDR 메모리 모델(AXI4 Slave)**이다.
문서의 **DDR Controller**는 이 메모리 모델을 의미한다.

---

## 2. 시스템 구성

| 구분 | 구성 요소 | 역할 |
| --- | --- | --- |
| DUT | `dma_controller` | MMIO로 설정된 SRC·DST·SIZE를 기반으로 AXI4 읽기·쓰기 트랜잭션을 수행하여 SRC 주소의 데이터를 DST 주소로 복사 |
| Interface | `axi4_if` | DUT와 메모리 모델 사이의 AXI4 신호 및 modport 정의 |
| Verification memory model | `ddr_controller` | AXI4 Slave로 DUT의 읽기·쓰기 요청에 응답 |
| Verification environment | `tb` | 클록·리셋 생성, 테스트 시나리오 실행, 결과 확인 및 functional coverage 측정 |

---

## 3. 시스템 구조도

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Testbench Environment                           │
│                                                                        │
│ ┌────────────────────────┐         MMIO          ┌─────────────────┐   │
│ │ Software Tasks         │◄─────────────────────►│ dma_controller  │   │
│ │                        │  ┌─────────────────┐  │      (DUT)      │   │
│ │ • write_dma_reg        │  │  Register Map   │  │ ┌─────────────┐ │   │
│ │ • read_dma_reg         │  │                 │  │ │    FSM      │ │   │
│ │ • wait_dma_completion  │  │ 0x00: CTRL      │  │ │   Engine    │ │   │
│ │ • verify_data_integrity│  │ 0x04: STAT      │  │ │ IDLE→SETUP  │ │   │
│ └────────────────────────┘  │ 0x08: SRC       │  │ │ →RD→WR→DONE │ │   │
│             │               │ 0x0C: DST       │  │ └─────────────┘ │   │
│             │               │ 0x10: SIZE      │  │                 │   │
│             │               │ 0x14: BYTES     │  │ ┌─────────────┐ │   │
│             │               └─────────────────┘  │ │   16-deep   │ │   │
│             │                                    │ │    FIFO     │ │   │
│             │                                    │ │   Buffer    │ │   │
│             │                                    │ └─────────────┘ │   │
│             │                                    └─────────────────┘   │
│             │                                             │            │
│             │                 AXI4 Interface              │            │
│             │         ┌─────────────────────────────┐     │            │
│             │         │ Write Addr (AW) Channel     │     │            │
│             │         │ Write Data (W) Channel      │     │            │
│             │         │ Write Resp (B) Channel      │     │            │
│             │         │ Read Addr (AR) Channel      │     │            │
│             │         │ Read Data (R) Channel       │     │            │
│             │         └─────────────────────────────┘     │            │
│             │                                             │            │
│             │                                             ▼            │
│             ▼                                    ┌─────────────────┐   │
│ ┌──────────────────────────────────────┐         │ ddr_controller  │   │
│ │      Functional Coverage Model       │         │ (Memory Model)  │   │
│ │                                      │         │ ┌─────────────┐ │   │
│ │ • cp_size                            │         │ │   Memory    │ │   │
│ │ • cp_dma_state/cp_state_transitions  │         │ │   Array     │ │   │
│ │ • cp_src_alignment/cp_dst_alignment  │         │ │  [0:1023]   │ │   │
│ │ • cp_burst_len                       │         │ │             │ │   │
│ │ • cx_size_alignment                  │         │ │  4KB Model  │ │   │
│ └──────────────────────────────────────┘         │ └─────────────┘ │   │
│                                                  │ ┌─────────────┐ │   │
│                                                  │ │   Latency   │ │   │
│                                                  │ │    Model    │ │   │
│                                                  │ │  (3 cycles) │ │   │
│                                                  │ └─────────────┘ │   │
│                                                  └─────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

## 4. 데이터 흐름도

```text
[Phase 1: Configuration]
Software → MMIO → DMA Registers
   ↓
SRC_ADDR = 0x00000000
DST_ADDR = 0x00000400
SIZE = 256 bytes
CTRL = enable | start | irq_en
─────────────────────────────────────────
[Phase 2: Read Burst]
DMA → AXI AR Channel → DDR
   ↓
DDR → AXI R Channel → DMA FIFO
   ↓
FIFO[0] = 0xCAFE0000
FIFO[1] = 0xCAFE0001
...
FIFO[15] = 0xCAFE000F
─────────────────────────────────────────
[Phase 3: Write Burst]
DMA FIFO → AXI W Channel → DDR
   ↓
DDR[256] = 0xCAFE0000
DDR[257] = 0xCAFE0001
...
DDR[271] = 0xCAFE000F
─────────────────────────────────────────
[Phase 4: Completion]
DMA → Interrupt → Software
   ↓
STATUS.done = 1
BYTES_DONE = 256
```

### 동작 요약

Testbench가 MMIO로 소스 주소, 목적지 주소, 전송 크기를 설정하고 DMA를 시작하면,
DMA Controller는 소스 데이터를 AXI4 burst로 읽어 내부 FIFO에 저장한 뒤 목적지 주소로
쓴다. 남은 데이터가 있으면 같은 과정을 반복하고, 전체 전송이 끝나면 완료 상태와
인터럽트를 생성한다.

## 5. DUT: `dma_controller`

### 5.1 DMA 레지스터 맵

| Offset | 이름 | 접근 | 필드 | 설명 |
| --- | --- | --- | --- | --- |
| `0x00` | `CTRL` | R/W | `[15:8] channel_id`, `[2] irq_en`, `[1] start`, `[0] enable` | 시작, 인터럽트 및 AXI ID 설정 |
| `0x04` | `STAT` | R | `[11:8] error_code`, `[2] error`, `[1] done`, `[0] busy` | DMA 실행 상태와 오류 정보 |
| `0x08` | `SRC` | R/W | `[31:0] src_addr` | 소스 시작 주소 |
| `0x0C` | `DST` | R/W | `[31:0] dst_addr` | 목적지 시작 주소 |
| `0x10` | `SIZE` | R/W | `[31:0] size` | 전체 전송 크기(byte) |
| `0x14` | `BYTES` | R | `[31:0] bytes_done` | R 채널에서 수신한 누적 byte 수 |

설정 순서는 `SRC → DST → SIZE → CTRL.start`이다. `enable`은 저장만 되고 실행을 제한하지
않으며, `irq_en`은 완료·오류 인터럽트를 제어한다.

### 5.2 DMA 제어 흐름

정상 흐름은 `IDLE → SETUP → RD_ADDR → RD_DATA → WR_ADDR → WR_DATA → WR_RESP`이다.
남은 데이터가 있으면 `NEXT → SETUP`을 반복하고, 완료하면 `DONE → IDLE`로 전이한다.
설정 오류는 `ERROR`로 전이한다. AXI 설정은 32-bit address/data, 4-bit ID, 4-byte beat,
INCR burst로 고정된다.

### 5.3 버스트 분할 및 FIFO 동작

AXI4 데이터 폭은 32-bit이므로 한 beat마다 4 byte를 전송한다. DMA는 전체 데이터를 한 번에
복사하지 않고, `bytes_left`에 따라 64 byte, 16 byte 또는 4 byte 크기의 버스트로 나누어
처리한다.

| `bytes_left` | 버스트 길이 | `ARLEN`/`AWLEN` | 버스트당 전송량 |
| --- | ---: | ---: | ---: |
| 64 byte 이상 | 16 beats | 15 | 64 byte |
| 16~63 byte | 4 beats | 3 | 16 byte |
| 4~15 byte | 1 beat | 0 | 4 byte |
| 1~3 byte | 지원하지 않음 | - | `error_code=0x2` |

`ARLEN`과 `AWLEN`에는 AXI4 규칙에 따라 실제 beat 수보다 1 작은 값을 설정한다. 예를 들어
16 beats를 전송할 때는 `AxLEN=15`가 된다.

각 버스트에서는 다음 순서로 데이터를 복사한다.

```text
SRC에서 한 버스트 읽기
        ↓
읽은 데이터를 FIFO에 저장
        ↓
FIFO의 데이터를 DST에 한 버스트 쓰기
        ↓
남은 데이터가 있으면 다음 버스트 반복
```

내부 FIFO는 `16 × 32-bit` 크기로, 최대 버스트인 16 beats(64 byte)의 데이터를 저장한다.
DMA는 한 버스트의 데이터를 모두 FIFO에 저장한 후 해당 데이터를 목적지로 전송한다.

읽기 beat가 수신될 때마다 `cur_src`는 4씩 증가하고, `bytes_left`는 4씩 감소하며,
`bytes_done`은 4씩 증가한다. 쓰기 beat가 전송될 때마다 `cur_dst`가 4씩 증가한다. 마지막
버스트의 쓰기 응답을 받은 시점에 `bytes_left==0`이면 전송을 완료한다.

전송 크기가 4의 배수가 아니면 전송 가능한 4-byte 단위까지 먼저 복사한 후, 남은 1~3
byte에 대해 `error_code=0x2`를 발생시킨다. 예를 들어 `SIZE=15`이면 12 byte를 복사한 뒤
남은 3 byte에서 오류가 발생한다.

---

## 6. 검증용 DDR 메모리 모델

`ddr_controller`는 실제 DDR 제어 로직이 아니라 DMA의 AXI4 요청에 응답하는 단순 메모리 모델이다.

| 항목 | 구현 내용 |
| --- | --- |
| 메모리 | 1,024 × 32-bit(4 KB), `address[11:2]`를 word index로 사용 |
| 초기값 | `mem[0:63] = 0xCAFE_0000 + index`, 나머지는 0 |
| Read latency | `R_LAT=3` 초기 지연 카운터 적용 |
| Response | `RRESP`, `BRESP` 모두 `OKAY` 응답 |

---

## 7. Baseline 구현 범위 및 제한 사항

- 주소는 4-byte aligned, 전송 크기는 4의 배수로 제한된다.
- DMA는 `RRESP`와 `RLAST`를 검사하지 않는다.
- DMA에서 `BRESP` 오류는 `stat.error`와 `error_code=0x3`을 설정하지만, DDR 메모리 모델이 `BRESP`를 항상 `OKAY`로 반환하므로 해당 에러 코드를 검증할 수 없다.
- 한 번에 한 burst를 읽은 뒤 쓰는 순차 구조이며 multiple outstanding transaction을 지원하지
  않는다.
