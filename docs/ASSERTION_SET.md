# AXI4 W Channel Assertion Set

## 1. 개요

본 문서는 DMA controller의 AXI4 W 채널이 backpressure 상황의 신호 유지와 write burst
마지막 beat의 WLAST timing 조건을 준수하는지 확인하기 위한 assertion 항목과 판정 기준을
정의한다. Checker는 DUT와 DDR memory model 사이의 AXI4 interface를 관측하며 DUT 동작에는
영향을 주지 않는다.

## 2. 검증 범위

- Sampling clock: `axi.aclk` 상승 edge
- Reset 조건: `axi.aresetn=0`인 동안 assertion 비활성화
- 검증 대상: AXI4 W 채널의 `WVALID`, `WREADY`, `WDATA`, `WSTRB`, `WLAST`, burst 정보
  `AWLEN`과 DUT의 `w_beats_sent`
- 구현 파일: [`axi_checker.sv`](../dv/checkers/axi_checker.sv)
- Checker instance: `tb.axi_w_checker`

## 3. Assertion 항목

| ID | Property | 조건 | 검증 내용 | Violation counter |
|---|---|---|---|---|
| A-01 | `p_w_payload_stable_on_stall` | `WVALID && !WREADY` | 다음 cycle까지 `WDATA`, `WSTRB`, `WLAST`가 유지되는지 확인 | `vio_w_payload_stable_on_stall` |
| A-02 | `p_wvalid_hold` | `WVALID && !WREADY` | 다음 cycle에도 `WVALID=1`이 유지되는지 확인 | `vio_wvalid_hold` |
| A-03 | `p_wlast_timing` | `WVALID && WREADY` | 마지막 beat의 WLAST 누락과 마지막 beat 이전의 잘못된 WLAST 활성화 확인 | `vio_wlast_timing` |

`p_wlast_timing`은 마지막 beat에서 `WLAST=1`인지 확인하는 동시에, 마지막 beat가 아닌
handshake에서 `WLAST=0`인지도 확인한다. 따라서 마지막 beat의 WLAST 누락과 마지막 beat
이전의 잘못된 WLAST 활성화를 하나의 property로 검출한다.

각 assertion이 실패하면 `$error`를 발생시키고 해당 violation counter와 전체 counter인
`vio_total`을 증가시킨다. `dma_test`와 `dma_regression_test`의 report phase에서 assertion별
발생 횟수와 최종 PASS/FAIL을 출력한다.

## 4. 판정 기준

- `vio_w_payload_stable_on_stall=0`
- `vio_wvalid_hold=0`
- `vio_wlast_timing=0`
- `vio_total=0`

모든 counter가 0이면 AXI4 W channel checker를 PASS로 판정한다. 하나 이상의 violation이
발생하면 assertion error와 report 결과를 함께 확인하여 원인을 분석한다.
