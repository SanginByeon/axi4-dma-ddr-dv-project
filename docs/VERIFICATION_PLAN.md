# AXI4 기반 DMA Controller Verification Plan

## 1. 개요

본 문서는 AXI4 기반 `dma_controller`의 기능, 오류 처리 및 W 채널 protocol 준수 여부를
검증하기 위한 계획을 정의한다. Step 2 및 Step 3에서 구축한 UVM 환경과 DDR memory model의
backpressure·BRESP error injection 기능을 기반으로 directed test와 constrained-random
test를 확장하고 functional coverage closure를 수행한다.

Coverage 항목과 sampling 기준은 [`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md)에 정의한다.
AXI4 W channel assertion과 판정 기준은 [`ASSERTION_SET.md`](./ASSERTION_SET.md)에 정의한다.
시나리오별 stimulus matrix와 예상 결과는 [`TEST_PLAN.md`](./TEST_PLAN.md)에 정의한다.

## 2. 검증 목표

- 4-byte 정렬 주소 사이에서 source data가 destination으로 정확히 복사되는지 확인
- 전송 잔량에 따라 1·4·16-beat burst가 선택되고 multi-burst와 마지막 잔여 burst가
  정상 처리되는지 확인
- W 채널 backpressure 중 data 손실·중복·순서 변경 없이 전송이 완료되는지 확인
- 지원하지 않는 전송 크기와 `BRESP=SLVERR`가 각각 정의된 오류 상태로 처리되는지 확인
- 오류 처리 후 다음 DMA transaction을 정상적으로 수행할 수 있는지 확인
- Backpressure 중 AXI4 W 채널의 VALID/READY handshake와 payload 안정성, 마지막 beat의
  WLAST timing을 assertion으로 확인
- 계획한 functional coverage bin과 cross를 모두 충족하고 미도달 항목의 원인을 기록

## 3. 검증 범위

### 3.1 검증 대상

| 구분 | 대상 | 검증 내용 |
|---|---|---|
| DUT | `dma_controller` | MMIO 설정, AXI4 read/write burst, FIFO 중계, 완료·오류 상태 및 interrupt |
| AXI4 W 채널 | `WVALID`, `WREADY`, `WDATA`, `WSTRB`, `WLAST` | Backpressure 중 protocol 준수 및 data 안정성 |
| AXI4 B 채널 | `BVALID`, `BREADY`, `BRESP` | OKAY 완료 및 SLVERR 오류 처리 |
| 검증용 Slave | `ddr_memory_model` | Random WREADY backpressure 및 BRESP SLVERR 생성 |

### 3.2 검증 조건

- 주소는 4-byte aligned로 제한한다.
- Source와 destination 영역은 4 KB memory 범위 안에 위치하며 서로 중첩하지 않는다.
- 전송 크기는 memory 범위와 비중첩 조건을 고려하여 1~2,048 byte로 제한한다.
- 정상 완료 시나리오는 4-byte 배수의 전송 크기를 사용한다.
- 1~3 byte 및 4-byte 배수가 아닌 크기는 size error 경로 검증에만 사용한다.
- `enable=1`, `start=1`, `irq_en=1`을 Step 4의 기본 제어 조건으로 사용한다.

### 3.3 제외 범위

다음 항목은 현재 DUT 또는 memory model의 지원 범위를 벗어나거나 본 프로젝트의 검증 목표에
포함되지 않으므로 Step 4 coverage closure 대상에서 제외한다.

- 4-byte unaligned address, sub-word transfer 및 source/destination 영역 중첩
- 4 KB memory 범위를 벗어나는 접근과 2,048 byte를 초과하는 비중첩 전송
- Multiple outstanding transaction 및 out-of-order response
- AXI4 AR/R/AW 채널 backpressure와 `RRESP` error injection
- `BRESP`의 EXOKAY·DECERR 응답
- `enable=0`, `start=0`, `irq_en=0` 및 AXI ID 조합 검증
- 고정값인 `AxSIZE`, `AxBURST`, `WSTRB`의 조합 검증
- 실제 전송 구간을 기준으로 한 throughput 측정 및 성능 최적화

Coverage와 관련된 제외 항목은 미도달 bin으로 남기지 않고 coverage plan에 근거를 명시한다.

## 4. 검증 전략

### 4.1 Stimulus

- Directed test로 burst 경계, size error, backpressure, SLVERR 및 오류 복구 조건과 주요
  coverage bin을 우선 검증
- S7에서 5개의 constrained-random transaction을 생성하여 정렬·범위·비중첩 constraint와
  무작위 정상 전송 조합을 추가 확인
- S7은 통계적 random regression이나 coverage closure의 주된 수단이 아닌 보완 test로 사용
- 실제 생성된 S7 transaction 값을 simulation log에 기록

### 4.2 결과 판정

| 결과 유형 | 기대 결과 |
|---|---|
| 정상 전송 | `done=1`, `error=0`, `error_code=0x0`, source와 destination data 일치 |
| Size error | `done=0`, `error=1`, `error_code=0x2`, error interrupt 및 `S_SETUP → S_ERROR` 관측 |
| BRESP SLVERR | `done=0`, `error=1`, `error_code=0x3`, error interrupt 및 `S_WR_RESP → S_ERROR` 관측 |
| 오류 복구 | 오류 transaction 이후 시작한 정상 transaction이 정상 완료 |

기존 Driver는 DUT의 error status를 `uvm_error`로 보고하고, Scoreboard는 오류 종류와 관계없이
요청된 전체 전송 구간의 source와 destination을 비교한다. Step 4에서는 이 동작을 변경하지
않는다. 따라서 정상 전송은 UVM 결과와 데이터 비교로 판정하고, 의도적으로 오류를 발생시키는
negative test는 `error_code`, interrupt, FSM transition 및 functional coverage로 오류 경로
진입을 확인한다. Negative test에서 발생한 예상 UVM error와 Scoreboard 결과는 simulation
log에 시나리오별로 구분하여 기록한다.

Driver는 `bytes_done`을 읽어 `UVM_HIGH` 참고 로그로 출력하지만, 요청한 `size`와 자동으로
비교하지 않으므로 PASS/FAIL 판정 항목에는 포함하지 않는다.

### 4.3 검증 및 판정 구성

- Driver 판정: MMIO 설정 후 STATUS의 정상·오류 종료와 timeout을 확인하고, `bytes_done`은
  참고용으로 읽어 `UVM_HIGH` 로그로 출력
- Monitor 수집: MMIO 설정값과 완료·오류 interrupt를 기준으로 transaction을 수집하여
  Scoreboard로 전달
- Scoreboard 판정: 요청 크기 전체의 source와 destination data를 비교하고, 생성한
  transaction 수와 실제 처리 수의 일치 여부 확인
- AXI4 assertion:
  - `WVALID && !WREADY` 동안 `WVALID` 유지
  - `WVALID && !WREADY` 동안 `WDATA`, `WSTRB`, `WLAST` 유지
  - `WVALID && WREADY`에서 `WLAST`와 `AWLEN` 기준 마지막 beat 일치

## 5. 테스트 시나리오

시나리오별 전송 크기, 주소, backpressure 및 error injection 설정값은
[`TEST_PLAN.md`](./TEST_PLAN.md)에 정의한다.

| ID | 시나리오 | 주요 조건 | 판정 항목 |
|---|---|---|---|
| S1 | 정상 전송 경계값 | 4, 12, 16, 60, 64, 68, 80, 256, 1,024, 1,028, 2,048B | 기준 전송, burst 선택, tail burst, 전체 data 일치 |
| S2 | Size error | 1, 2, 3, 15B | `S_SETUP → S_ERROR`, `error_code=0x2` 및 예상 negative log |
| S3 | W backpressure | 1·4·16-beat burst와 10%·50%·90% 조건 조합 | Stall 중 payload 안정성, data 일치, 정상 완료 |
| S4 | BRESP error injection | 유효 크기, backpressure 없음, SLVERR 주입 | `S_WR_RESP → S_ERROR`, `error_code=0x3` 및 예상 negative log |
| S5 | Backpressure + SLVERR | 유효 크기, backpressure 적용, SLVERR 주입 | W 전송 안정성, B response 오류 경로 및 예상 negative log |
| S6 | 오류 복구 | Size error 또는 SLVERR 직후 정상 전송 | `S_ERROR → S_IDLE` 및 후속 정상 완료 |
| S7 | Constrained random | 정렬 주소, 비중첩 영역, 크기·주소·backpressure 조합 5건 | Constraint 기반 정상 전송 조합과 data 일치 추가 확인 |

전체 테스트 시나리오의 source와 destination 주소는 4 KB 범위 안의 low/mid/high memory
region에 분산하여 배치한다.

## 6. 검증 항목 추적표

| ID | 검증 항목 | Stimulus | Checker | Coverage |
|---|---|---|---|---|
| V-01 | 정상 data copy | S1, S7 | Scoreboard, STATUS 정상 완료 확인 | C-TX-01·02·04·05·08 |
| V-02 | Burst 경계와 multi-burst | S1 | Scoreboard, WLAST assertion 및 coverage 분석 | C-FSM-02·03·04, C-AXI-01·05 |
| V-03 | Size error 처리 | S2 | STATUS, interrupt 및 negative log | C-TX-01·03·08, X-TX-01, C-FSM-02·03 |
| V-04 | Backpressure 내성 | S3, S7 | Scoreboard, W assertion | C-TX-06, C-AXI-02·03·04, X-AXI-01 |
| V-05 | BRESP SLVERR 처리 | S4 | STATUS, interrupt 및 negative log | C-TX-07·08, X-TX-02, C-FSM-02, C-AXI-06·07, X-AXI-02 |
| V-06 | Backpressure와 SLVERR 결합 | S5 | Negative log, Scoreboard 및 W assertion | C-TX-06·07·08, X-TX-03, C-AXI-03·04·06 |
| V-07 | 오류 후 복구 | S6 | 후속 transaction 정상 완료 | C-FSM-02 |
| V-08 | AXI4 W channel protocol | S1, S3, S5, S7 | Assertion checker | C-AXI-03·04·05 |

## 7. 완료 기준

- 계획된 directed test와 5건의 constrained-random test가 모두 종료
- 정상 전송 시나리오의 Scoreboard mismatch 및 X/Z 검출 0건
- Negative test의 예상 UVM error와 Scoreboard 결과를 시나리오별로 기록
- 예상 범위를 벗어난 UVM warning/error/fatal 및 timeout 0건
- 예상 transaction 수와 실제 검사 수 일치
- AXI4 assertion violation 0건
- [`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md)에 정의한 reachable coverpoint와 cross 100% 달성
- 미도달 또는 제외한 항목은 사유와 후속 조치를 문서화
