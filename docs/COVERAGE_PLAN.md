# AXI4 기반 DMA Controller Functional Coverage Plan

## 1. 개요

본 문서는 [`VERIFICATION_PLAN.md`](./VERIFICATION_PLAN.md)의 검증 항목이 실제로 실행되었는지
측정하기 위한 functional coverage 구조, sampling 시점, coverpoint, cross 및 closure 기준을
정의한다.

기존의 단일 `cg_dma_coverage @(posedge tb.clk)` 구조는 서로 다른 의미의 값을 매 cycle
중복 sampling한다. Step 4에서는 coverage를 transaction, DMA FSM, AXI event의 세 그룹으로
분리한다.

## 2. Coverage 구조

- 구현 파일: [`coverage.sv`](../dv/coverage.sv)

| Covergroup | Sampling | 측정 대상 | Coverpoint | Cross |
|---|---|---|---:|---:|
| `cg_dma_transaction` | 완료·오류 interrupt 상승 edge | 설정값, 주소 및 실제 종료 결과 | 8 | 3 |
| `cg_dma_fsm` | `tb.clk` 상승 edge | FSM state, state transition, `S_SETUP` 및 tail 분기 | 4 | 0 |
| `cg_axi_event` | `tb.clk` 상승 edge와 channel별 `iff` | AWLEN, W handshake/stall, WLAST, BRESP | 7 | 2 |
| **합계** |  |  | **19** | **5** |

Transaction coverage는 완료 또는 오류 interrupt가 발생할 때 transaction 설정과 실제 결과를
한 번 sampling한다. FSM과 AXI event coverage는 clock 기반으로 수집하되, 해당 상태 또는
handshake가 성립한 cycle만 `iff`로 제한한다.

```systemverilog
covergroup cg_dma_transaction
    @(posedge tb.mmio.dma_done_int or posedge tb.mmio.dma_error_int);
endgroup

covergroup cg_dma_fsm @(posedge tb.clk);
endgroup

covergroup cg_axi_event @(posedge tb.clk);
endgroup
```

## 3. Transaction Coverage

### 3.1 Coverpoint

| ID | Coverpoint | Sampling 조건 | 목표 bin | 목적 |
|---|---|---|---|---|
| C-TX-01 | `cp_size_boundary` | DMA done/error interrupt | 1, 2, 3, 4, 12, 15, 16, 60, 64, 68, 80, 256, 1,024, 1,028, 2,048B | 미지원 크기, 기준 전송, burst 경계, tail 및 최대 전송 확인 |
| C-TX-02 | `cp_size_range` | DMA done/error interrupt, 4-byte 배수 | `size_tiny`=4~16, `size_small`=20~256, `size_medium`=260~1,024, `size_large`=1,028~2,048B | 정상 전송의 크기 분포 확인 |
| C-TX-03 | `cp_size_category` | DMA done/error interrupt | 4B 미만 / 4B 이상 비배수 / 4B 배수 | 정상·오류 크기 조건 분류 |
| C-TX-04 | `cp_src_region` | DMA done/error interrupt | low / mid / high | Source 시작 주소의 4 KB memory 영역 분산 |
| C-TX-05 | `cp_dst_region` | DMA done/error interrupt | low / mid / high | Destination 시작 주소의 4 KB memory 영역 분산 |
| C-TX-06 | `cp_backpressure_class` | DMA done/error interrupt | `bp_none`=0%, `bp_low`=1~30%, `bp_medium`=31~70%, `bp_high`=71~99% | 응답 지연 강도별 stimulus 확인 |
| C-TX-07 | `cp_error_inject` | DMA done/error interrupt | off / on | 정상 BRESP와 의도적 SLVERR 조건 확인 |
| C-TX-08 | `cp_error_code` | DMA done/error interrupt | normal=`0x0`, size error=`0x2`, SLVERR=`0x3` | Stimulus에 대응하는 실제 종료 결과 확인 |

Transfer size는 모든 숫자를 균등하게 채우는 목적이 아니라 DUT의 의사결정이 달라지는
경계값을 확인하기 위한 것이다. Constrained-random에서 생성한 기타 유효 크기는 constraint
기반 정상 전송의 추가 확인에 사용하며, 별도 closure bin을 자동 생성하지 않는다.

### 3.2 Cross

| ID | Cross | 목표 조합 | 목적 |
|---|---|---|---|
| X-TX-01 | `cx_size_result` | 정상 크기→`0x0`, 4B 미만·비배수→`0x2` | 전송 크기 조건과 실제 종료 결과 연결 |
| X-TX-02 | `cx_inject_result` | off→`0x0`/`0x2`, on→`0x3` | Error injection 설정과 실제 오류 코드 연결 |
| X-TX-03 | `cx_inject_backpressure` | Error injection off/on × `bp_none`/`bp_low`/`bp_medium`/`bp_high` | SLVERR 단독 및 backpressure 결합 조건 확인 |

결과 인과관계를 확인하는 X-TX-01과 X-TX-02는 유효 조합만 named bin으로 정의하고 나머지는
ignore bin으로 제외한다. X-TX-03은 error injection과 backpressure 설정의 8개 조합을 모두
목표로 사용한다.

## 4. DMA FSM Coverage

### 4.1 Coverpoint

| ID | Coverpoint | Sampling 조건 | 목표 bin | 목적 |
|---|---|---|---|---|
| C-FSM-01 | `cp_state` | `clk` 상승 edge, reset 해제 | `S_IDLE`, `S_SETUP`, `S_RD_ADDR`, `S_RD_DATA`, `S_WR_ADDR`, `S_WR_DATA`, `S_WR_RESP`, `S_NEXT`, `S_DONE`, `S_ERROR` | DMA의 모든 상태 도달 확인 |
| C-FSM-02 | `cp_state_transition` | `clk` 상승 edge, reset 해제 | 정상 완료, multi-burst 반복, size·BRESP 오류 및 오류 복구 전이 | 정상·반복·오류·복구 경로 실행 확인 |
| C-FSM-03 | `cp_setup_case` | `S_SETUP && !setup_complete` | `bytes_left=1~3`, `4~15`, `16~63`, `64 이상` | Burst 길이 결정 분기 확인 |
| C-FSM-04 | `cp_tail_setup_case` | 64B 초과 정상 전송의 잔여 `S_SETUP` | 1-beat tail=`4~15`, 4-beat tail=`16~63` | Multi-burst의 잔여 구간 처리 확인 |

`bytes_left`는 `S_SETUP`의 burst 결정이 실제로 실행되는 cycle에만 sampling한다. 다른
상태에서 유지되는 값은 coverage에 포함하지 않는다. Tail setup은 초기 전송 크기가 64B를
초과하는 4-byte 배수이고, 64B full burst 처리 후 잔여 크기가 4~63B인 transaction만
대상으로 한다.

## 5. AXI Event Coverage

### 5.1 Coverpoint

| ID | Coverpoint | Sampling 조건 | 목표 bin | 목적 |
|---|---|---|---|---|
| C-AXI-01 | `cp_awlen` | `AWVALID && AWREADY` | 0(1 beat), 3(4 beats), 15(16 beats) | 실제 write burst 길이 확인 |
| C-AXI-02 | `cp_backpressure_cfg_at_aw` | `AWVALID && AWREADY` | `bp_none` / `bp_low` / `bp_medium` / `bp_high` | Write burst에 적용되는 backpressure 설정 확인 |
| C-AXI-03 | `cp_w_event` | `WVALID` | accepted=`WREADY`, stalled=`!WREADY` | W handshake와 실제 stall 발생 확인 |
| C-AXI-04 | `cp_stall_awlen` | `WVALID && !WREADY` | AWLEN 0 / 3 / 15 | Burst 길이별 실제 stall 발생 확인 |
| C-AXI-05 | `cp_wlast_awlen` | `WVALID && WREADY && WLAST` | AWLEN 0 / 3 / 15 | Burst 길이별 WLAST handshake 확인 |
| C-AXI-06 | `cp_bresp` | `BVALID && BREADY` | OKAY / SLVERR | 실제 write response 확인 |
| C-AXI-07 | `cp_error_inject_at_b` | `BVALID && BREADY` | off / on | B response 시점의 error injection 설정 확인 |

Backpressure 설정값은 AW handshake에서 해당 write burst에 적용될 값을 sampling하고, 실제
stall은 W channel에서 `WVALID && !WREADY`가 관측된 AWLEN별로 구분한다. `AWLEN` 0·3·15
이외의 값은 현재 DUT가 생성하지 않으므로 illegal bin으로 처리한다.

### 5.2 Cross

| ID | Cross | 목표 조합 | 목적 |
|---|---|---|---|
| X-AXI-01 | `cx_backpressure_awlen` | `bp_none`/`bp_low`/`bp_medium`/`bp_high` × AWLEN 0/3/15 | Burst 길이별 backpressure 설정 확인 |
| X-AXI-02 | `cx_bresp_error_inject` | off×OKAY, on×SLVERR | Error injection 설정과 실제 response 연결 |

## 6. Coverage에서 제외하는 항목

| 항목 | 처리 | 근거 |
|---|---|---|
| Unaligned address | Coverage bin 미생성 | DUT와 transaction이 4-byte aligned access만 지원 |
| 4 KB 외부·중첩 주소 | Coverage bin 미생성 | Memory 범위와 transaction constraint 위반 |
| `AWLEN` 0·3·15 이외 | Illegal bin | DUT의 burst 분할 규칙상 생성되면 안 됨 |
| EXOKAY·DECERR·RRESP error | Coverage 제외 | DDR memory model이 생성하지 않음 |
| `AxSIZE`, `AxBURST`, `WSTRB` 조합 | Coverage 제외 | DUT에서 고정값으로 사용 |

## 7. Coverage 완료 기준

- 세 covergroup의 계획된 coverpoint bin과 유효 cross bin 100%
- Transaction당 transaction covergroup sampling 정확히 1회
- AW, W, B event가 각 handshake 또는 stall cycle에서만 sampling되도록 `iff` 조건 적용
- Coverage를 채우기 위한 illegal stimulus나 의미 없는 cross hit 없음
- 정상 전송의 Scoreboard와 assertion 검증 PASS
- Negative test에서 발생한 예상 UVM error와 Scoreboard 결과를 시나리오별로 기록
- 최종 simulation log에 transaction 수, 실제 random 값, 항목별 coverage 및 overall coverage 기록
