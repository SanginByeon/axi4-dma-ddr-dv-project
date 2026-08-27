# DMA Backpressure Regression Plan

## 1. 개요

본 문서는 Step 4에서 functional coverage closure와 기능 검증을 완료한 DMA controller를
대상으로, 반복적인 AXI4 W 채널 backpressure 환경에서도 기존 정상 동작이 안정적으로
유지되는지 확인하기 위한 Step 5 regression 계획을 정의한다.

Step 5에서는 Step 4의 전체 시나리오를 반복하지 않고, 정상 전송과 backpressure 조건에
범위를 한정한 전용 regression sequence를 실행한다. Functional coverage 추가 달성이 아니라
반복 실행 중 발생할 수 있는 간헐적인 data mismatch, timeout 및 AXI4 protocol violation
검출을 목적으로 한다.

## 2. 목적

기능 검증이 완료된 DUT가 서로 다른 backpressure timing과 반복 전송 조건에서도 데이터 손실, timeout 또는 AXI4 protocol violation 없이 정상 동작하는지 확인하기 위함.

## 3. Regression 범위

### 3.1 검증 항목

- Backpressure 확률과 발생 시점이 달라져도 source data가 destination에 정확히 복사되는지 확인
- 반복 transaction 사이에서 data 누락·중복·순서 변경 및 이전 상태 누출이 없는지 확인
- 1·4·16-beat 및 multi-burst 전송이 높은 backpressure에서도 timeout 없이 완료되는지 확인
- AXI4 W 채널의 stall 중 payload 안정성, WVALID 유지 및 WLAST timing 준수 여부 확인
- W payload, FIFO prefetch 및 WLAST 관련 DUT 수정이 전송 크기별 정상 동작을 훼손하지 않았는지 확인

### 3.2 제외 범위

- Size error 및 BRESP SLVERR 오류 경로 반복 검증
- Functional coverage closure 재수행
- Throughput 측정 및 성능 비교

Size error, BRESP SLVERR 및 functional coverage는 Step 4에서 검증을 완료했으므로 Step 5의
반복 대상에서 제외한다.

## 4. 공통 설정

- `enable=1`, `start=1`, `irq=1`
- `error_inject=0`
- Source address: `0x0000`
- Destination address: `0x0800`
- Source와 destination은 4-byte aligned이며 4 KB memory 안에서 서로 중첩하지 않음
- 각 transaction 실행 전에 source memory를 검증용 data pattern으로 초기화
- DUT 내부 진행 로그는 비활성화하고 UVM verbosity는 `UVM_MEDIUM` 사용
- 실행마다 지정된 seed를 사용하고 결과 log에 해당 seed를 기록

Destination을 `0x0800`으로 설정하면 최대 크기인 1,028-byte 전송에서도 source 영역
`0x0000~0x0403`과 destination 영역 `0x0800~0x0C03`이 중첩되지 않는다.

## 5. Regression Matrix

각 seed에서는 backpressure 확률마다 아래 6개 전송 크기를 순차 실행한다.

| 전송 크기 | 주요 조건 |
|---:|---|
| 4B | 1-beat burst |
| 16B | 4-beat burst |
| 64B | 16-beat burst |
| 80B | 16-beat + 4-beat burst |
| 512B | Multi-burst |
| 1,028B | Multi-burst + 1-beat tail |

다음 10개 seed를 사용하며, seed마다 모든 backpressure 확률과 전송 크기의 조합을 한 번씩
실행한다.

```text
1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010
```

| Backpressure 확률 | Seed 수 | Seed당 Transaction | 합계 |
|---:|---:|---:|---:|
| 0% | 10 | 6 | 60 |
| 10% | 10 | 6 | 60 |
| 30% | 10 | 6 | 60 |
| 50% | 10 | 6 | 60 |
| 70% | 10 | 6 | 60 |
| 90% | 10 | 6 | 60 |
| **전체** | **10** | **36** | **360** |

하나의 seed에서는 6개 backpressure 확률과 6개 전송 크기를 조합한 36개 transaction을
실행한다. Step 5 전체 regression은 10회의 simulation과 총 360개 DMA transaction으로
구성한다.

## 6. 실행 구조

Regression은 seed별로 독립된 VCS simulation을 총 10회 실행한다. 각 simulation에서는
해당 seed를 설정하고 36개 transaction을 순차 실행한다.

EDA Playground의 Run Options에서 regression test와 numeric seed를 함께 지정한다.

```text
+UVM_TESTNAME=dma_regression_test +ntb_random_seed=1001
```

실행을 마칠 때마다 seed를 `1002`부터 `1010`까지 변경하여 동일한 regression test를 다시
실행한다. `+UVM_TESTNAME`을 지정하지 않으면 기존 Step 4의 `dma_test`가 기본 실행된다.

```systemverilog
foreach (backpressure_probs[p]) begin
    foreach (size_bytes[s]) begin
        // DMA transaction 생성 및 실행
    end
end
```

DDR memory model은 write burst가 진행되는 동안 매 cycle random backpressure 여부를 결정한다.
Seed가 달라지면 난수 순서가 달라지므로 동일한 backpressure 확률에서도 서로 다른 stall 발생
시점을 검증할 수 있다. 실패 발생 시 해당 seed를 다시 사용해 동일한 조건을 재현한다.

각 transaction의 scenario 이름에는 seed, backpressure 확률 및 전송 크기를 기록한다.

```text
[REGR-SEED1001-P90-S1028] Backpressure Regression
```

## 7. 구현 구성

다음 regression 전용 sequence와 test를 추가한다.

| 파일 | 역할 |
|---|---|
| `dma_regression_seq.sv` | 한 seed에서 backpressure 확률·전송 크기 matrix에 따라 36개 transaction 생성 |
| `dma_regression_test.sv` | Seed별 regression sequence 실행과 transaction·UVM error·AXI checker 기반 판정 |

기존 `dma_tx`, Driver, Monitor, Scoreboard, Agent, Environment 및 AXI checker는 변경 없이
재사용한다. Step 4의 S1~S7 sequence와 `TEST_PLAN.md`도 기존 검증 이력으로 보존한다.

## 8. 판정 기준

각 seed의 simulation이 다음 조건을 모두 만족하면 해당 실행을 PASS로 판정한다.

- 예상/검사 transaction: `36 / 36`
- UVM warning/error/fatal: 모두 0건
- Scoreboard data mismatch 및 X/Z 검출: 0건
- DMA timeout: 0건
- AXI4 W 채널 A-01~A-03 assertion violation: 0건
- 모든 backpressure 확률에서 6개 전송 크기 실행 완료

10개 seed가 모두 PASS하고 전체 예상/검사 transaction이 `360 / 360`이면 Step 5 regression을
최종 PASS로 판정한다. 하나의 seed에서라도 오류가 발생하면 전체 regression은 FAIL로 판정하고
해당 seed로 실패 조건을 재현한다.

Step 5의 최종 판정에는 functional coverage 결과를 사용하지 않는다. Coverage closure는
Step 4에서 완료했으며, Step 5에서는 반복 실행에 따른 기능 및 protocol 안정성을 판정한다.

## 9. 결과 보존

- Seed별 regression log: `runs/regression/step5_seed_<seed>.log`
- Step 5 결과 문서: `docs/steps/STEP5_REGRESSION.md`
- 실패 발생 시 재현 log와 분석 파형을 `runs/debug` 및 `docs/images/step5`에 추가

정상 완료한 regression은 10개 seed의 log를 증거 자료로 보존하며, 파형은 data mismatch,
timeout 또는 assertion violation이 발생해 추가 분석이 필요한 경우에만 저장한다.
