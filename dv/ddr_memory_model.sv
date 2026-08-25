// ============================================================================
// ddr_memory_model.sv - AXI4 Slave DDR Memory Model
//
// - DMA controller의 AXI4 read/write 요청에 응답하는 검증용 메모리 모델.
// - 1,024 x 32-bit 메모리와 고정 read latency를 제공.
// - UVM 전환에 따라 기존 memory pattern 초기화 로직을 제거하고 source data는 sequence가 preload.
// - 설정된 확률에 따라 AXI4 W channel에 random backpressure를 생성.
// - 설정에 따라 write burst 완료 시 BRESP로 SLVERR를 반환.
// - 실제 DDR controller 또는 PHY 동작은 모델링하지 않음.
// - Baseline의 ddr_controller를 역할에 맞게 이름을 변경하여 별도 파일로 분리.
// ============================================================================

module ddr_memory_model (
	axi4_if.slave axi, 	// AXI4 Slave interface
	ddr_model_if ddr_cfg	// DDR memory model 검증 조건 제어
);
	logic [31:0] mem [0:1023]; 				// 4KB 메모리 모델(워드 배열)
  
	localparam int R_LAT = 3; 				// 읽기 초기 지연 사이클 수
	logic rd_active; 						// 읽기 진행 플래그
	logic [31:0] rd_addr; 					// 현재 읽기 주소
	logic [7:0] rd_len; 					// 요청된 버스트 길이-1
	logic [7:0] rd_cnt; 					// 보낸 beat 수
	logic [2:0] rd_lat; 					// 초기 지연 카운터
	logic [3:0] rd_id_reg; 					// 읽기 ID 래치
  
	logic wr_active; 						// 쓰기 진행 플래그
	logic [31:0] wr_addr; 					// 현재 쓰기 주소
	logic [7:0] wr_len; 					// 요청된 버스트 길이-1
	logic [7:0] wr_cnt; 					// 받은 beat 수
	logic [3:0] wr_id_reg; 					// 쓰기 ID 래치
  
	logic bvalid_reg; 						// 내부 BRESP valid
	logic [1:0] bresp_reg; 					// 내부 BRESP 코드
	logic [3:0] bid_reg; 					// 내부 BRESP ID

	logic force_stall; 						// 1이면 WREADY를 비활성화
	logic [7:0] active_backpressure_prob; 	// 현재 write burst에 적용할 backpressure 확률
	logic active_error_inject; 				// 현재 write burst의 BRESP 오류 주입 설정
  
	logic r_valid_now; 						// 이번 사이클 rvalid 생성 여부
	logic r_fire; 							// rvalid & rready 핸드셰이크 성립
  
	assign axi.rresp = 2'b00; 				// 읽기 응답은 항상 OKAY
	assign axi.bresp = bresp_reg; 			// 쓰기 응답 코드 연결
	assign axi.bid = bid_reg; 				// 쓰기 응답 ID 연결
  
	assign axi.arready = (!rd_active); 					// 읽기 유휴 시 AR 수락
	assign axi.awready = (!wr_active) && !bvalid_reg; 	// 쓰기 유휴/응답없음 시 AW 수락
	assign axi.wready = wr_active && !force_stall; 		// Random stall이 없을 때만 W 데이터 수락

	// [W channel backpressure] : AW에서 확률을 고정하고 write burst 동안 매 사이클 random stall 결정
	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin
		if (!axi.aresetn) begin
			force_stall <= 1'b0;
			active_backpressure_prob <= '0;
			active_error_inject <= 1'b0;
		end else if (axi.awvalid && axi.awready) begin
			// 이번 write burst 전체에 동일한 backpressure와 BRESP 설정 적용
			active_backpressure_prob <= ddr_cfg.backpressure_prob;
			active_error_inject <= ddr_cfg.error_inject;

			// 첫 번째 W beat에 적용할 stall 여부 결정
			if (ddr_cfg.backpressure_prob == 0)
				force_stall <= 1'b0;
			else
				force_stall <=
					($urandom_range(0, 99) < ddr_cfg.backpressure_prob);
		end else if (wr_active) begin
			// Write burst가 진행되는 동안 매 사이클 독립적으로 stall 결정
			if (active_backpressure_prob == 0)
				force_stall <= 1'b0;
			else
				force_stall <=
					($urandom_range(0, 99) < active_backpressure_prob);
		end else begin
			force_stall <= 1'b0;

			// 이전 write burst의 오류 주입 설정이 다음 burst로 남지 않도록 초기화
			if (bvalid_reg && axi.bready)
				active_error_inject <= 1'b0;
		end
	end

	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin // 클록/리셋
      	if (!axi.aresetn) begin 				// 비동기 리셋
			rd_active <= 1'b0; rd_addr <= '0; rd_len <= '0; rd_cnt <= '0; rd_lat <= '0; rd_id_reg <= '0; // RD 초기화
			wr_active <= 1'b0; wr_addr <= '0; wr_len <= '0; wr_cnt <= '0; wr_id_reg <= '0; 				 // WR 초기화
			axi.rvalid <= 1'b0; axi.rlast <= 1'b0; axi.rid <= '0; axi.rdata <= '0; 						 // R채널 초기화
			bvalid_reg <= 1'b0; bresp_reg <= 2'b00; bid_reg <= '0; 										 // B채널 초기화
		end else begin
          	if (axi.arvalid && axi.arready) begin // AR 수락
              	rd_active <= 1'b1; 		// 읽기 시작
              	rd_addr <= axi.araddr; 	// 시작 주소 래치
              
              	rd_len <= axi.arlen; 	// 길이-1 래치
              	rd_cnt <= '0; 			// 카운터 초기화
              
              	rd_lat <= R_LAT[2:0]; 	// 초기 지연 설정
              	rd_id_reg <= axi.arid; 	// ID 래치
			end
          
          	r_valid_now = rd_active && (rd_lat==0); // 지연 후 rvalid 생성
			axi.rvalid <= r_valid_now; 				// rvalid 구동
			axi.rlast <= 1'b0; 						// 기본 last=0
			r_fire = r_valid_now && axi.rready; 	// 핸드셰이크 성립 여부
          
          	if (rd_active) begin 					 // 읽기 진행 중
              	if (rd_lat != 0) begin 				 // 아직 지연 단계
                  	rd_lat <= rd_lat - 1; 			 // 지연 카운트다운
                end else begin 						 // 데이터 출력 단계
					axi.rid <= rd_id_reg; 			 // ID 출력
                  	axi.rdata <= mem[rd_addr[11:2]]; // 워드 주소로 읽기
                  
                  	if (r_fire) begin 				 // 전송 성립 시
						rd_addr <= rd_addr + 4;		 // 다음 워드
                      	if (rd_cnt == rd_len) begin  // 마지막 beat면
							axi.rlast <= 1'b1; 		 // last=1
							rd_active <= 1'b0;		 // 읽기 종료
						end
						rd_cnt <= rd_cnt + 1;		 // 보낸 수 증가
					end
				end
			end
          
          	if (axi.awvalid && axi.awready) begin // AW 수락
              	wr_active <= 1'b1;				  // 쓰기 시작
              	wr_addr <= axi.awaddr;			  // 시작 주소 래치
              
              	wr_len <= axi.awlen;			  // 길이-1 래치
              	wr_cnt <= '0;				 	  // 카운터 초기화
              
              	wr_id_reg <= axi.awid;			  // ID 래치
			end
          
          	if (wr_active && axi.wvalid && axi.wready) begin // W 데이터 수신
              	mem[wr_addr[11:2]] <= axi.wdata;			 // 메모리 기록
              	wr_addr <= wr_addr + 4;						 // 다음 워드 주소
            	if (axi.wlast || (wr_cnt==wr_len)) begin	 // 마지막 beat 판단
					wr_active <= 1'b0;						 // 쓰기 종료
					bvalid_reg <= 1'b1;						 // BRESP 준비

					// AW handshake에서 latch한 설정에 따라 write response 결정
					if (active_error_inject)
						bresp_reg <= 2'b10;					 // SLVERR
					else
						bresp_reg <= 2'b00;					 // OKAY

					bid_reg <= wr_id_reg;					 // 응답 ID
				end
				wr_cnt <= wr_cnt + 1;						 // 받은 수 증가
			end

          	if (bvalid_reg && axi.bready) begin				 // BRESP 수락되면
              	bvalid_reg <= 1'b0;							 // 응답 완료
			end
		end
	end
  
  	assign axi.bvalid = bvalid_reg;							 // BRESP valid 외부 연결
  
endmodule
