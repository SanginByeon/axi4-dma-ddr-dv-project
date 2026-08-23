// ============================================================================
// axi4_if.sv - AXI4 Interface
//
// - DMA controller와 DDR memory model 사이의 AXI4 신호를 하나로 구성.
// - address/data/ID width를 parameter로 정의하고 필수 AXI4 channel 신호 제공.
// - master/slave modport를 통해 각 구성요소의 신호 방향을 구분.
// - Baseline design.sv의 AXI4 interface를 동작 변경 없이 별도 파일로 분리.
// ============================================================================

interface axi4_if #(
	parameter ADDR_WIDTH = 32, 	// 주소 폭
	parameter DATA_WIDTH = 32, 	// 데이터 폭
	parameter ID_WIDTH = 4 		// ID 폭
)(input logic aclk, aresetn); 	// 공통 클록/리셋
  
	// Write Address
	logic [ID_WIDTH-1:0] 	awid; 		// 쓰기 트랜잭션 ID
	logic [ADDR_WIDTH-1:0] 	awaddr; 	// 쓰기 시작 주소
	logic [7:0] 			awlen; 		// 버스트 길이-1
	logic [2:0] 			awsize;		// beat 바이트 수의 log2
	logic [1:0] 			awburst; 	// 버스트 타입(INCR/…)
	logic 					awvalid; 	// 주소 유효
	logic 					awready; 	// 주소 수락
  
	// Write Data
  	logic [DATA_WIDTH-1:0] 	 wdata; 	// 쓰기 데이터
	logic [DATA_WIDTH/8-1:0] wstrb; 	// 바이트 유효 마스크
	logic 					 wlast; 	// 마지막 beat 표시
	logic 					 wvalid; 	// 데이터 유효
	logic 					 wready; 	// 데이터 수락
  
  	// Write Resp
  	logic [ID_WIDTH-1:0] bid; 	 // 응답 ID
 	logic [1:0] 		 bresp;  // 응답 코드
  	logic 				 bvalid; // 응답 유효
	logic 				 bready; // 응답 수락
  
	// Read Address
  	logic [ID_WIDTH-1:0] 	arid; 	 // 읽기 트랜잭션 ID
  	logic [ADDR_WIDTH-1:0] 	araddr;  // 읽기 시작 주소
  	logic [7:0] 			arlen; 	 // 버스트 길이-1
  	logic [2:0] 			arsize;  // beat 바이트 수의 log2
	logic [1:0] 			arburst; // 버스트 타입
	logic 					arvalid; // 주소 유효
	logic 					arready; // 주소 수락

  	// Read Data
	logic [ID_WIDTH-1:0] 	rid; 	// 데이터 ID
	logic [DATA_WIDTH-1:0] 	rdata; 	// 읽기 데이터
	logic [1:0] 			rresp; 	// 읽기 응답
	logic 					rlast; 	// 마지막 beat 표시
	logic 					rvalid; // 데이터 유효
	logic 					rready; // 데이터 수락
  
	// Master
	modport master (
		// write address
		output awid, awaddr, awlen, awsize, awburst, awvalid, // 마스터가 구동
		input awready, 										  // 슬레이브 수락
		// write data
		output wdata, wstrb, wlast, wvalid, 				  // 마스터 데이터 구동
		input wready, 										  // 슬레이브 수락
		// write resp
		input bid, bresp, bvalid, 							  // 슬레이브 응답 수신
		output bready, 										  // 응답 수락 의사
		// read address
		output arid, araddr, arlen, arsize, arburst, arvalid, // 마스터 주소 구동
		input arready, 										  // 슬레이브 수락
		// read data
		input rid, rdata, rresp, rlast, rvalid, 			  // 데이터 수신
		output rready, 										  // 수락 의사
		// common
		input aclk, aresetn 								  // 공통 클록/리셋
	);
  
	// Slave
	modport slave (
	// write address
	input awid, awaddr, awlen, awsize, awburst, awvalid, // 주소/속성 수신
	output awready, 									 // 수락
	// write data
	input wdata, wstrb, wlast, wvalid, 					 // 데이터 수신
	output wready, 										 // 수락
	// write resp
	output bid, bresp, bvalid,							 // 응답 제공
	input bready, 										 // 수락 수신
	// read address
	input arid, araddr, arlen, arsize, arburst, arvalid, // 주소/속성 수신
	output arready, 									 // 수락
	// read data
	output rid, rdata, rresp, rlast, rvalid,			 // 데이터/응답 제공
	input rready,										 // 수락 수신
	// common
	input aclk, aresetn 								 // 공통 클록/리셋
	);
endinterface
