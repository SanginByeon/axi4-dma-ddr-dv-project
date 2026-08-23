// ============================================================================
// ddr_memory_model.sv - AXI4 Slave DDR Memory Model
//
// - DMA controller의 AXI4 read/write 요청에 응답하는 검증용 메모리 모델.
// - 1,024 x 32-bit 메모리와 고정 read latency를 제공.
// - 실제 DDR controller 또는 PHY 동작은 모델링하지 않음.
// - Baseline의 ddr_controller를 역할에 맞게 이름을 변경하여 별도 파일로 분리.
// ============================================================================

module ddr_memory_model (axi4_if.slave axi); 	// 인터페이스를 슬레이브로 사용
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
  
	logic r_valid_now; 						// 이번 사이클 rvalid 생성 여부
	logic r_fire; 							// rvalid & rready 핸드셰이크 성립
  
	assign axi.rresp = 2'b00; 				// 읽기 응답은 항상 OKAY
	assign axi.bresp = bresp_reg; 			// 쓰기 응답 코드 연결
	assign axi.bid = bid_reg; 				// 쓰기 응답 ID 연결
  
  	assign axi.arready = (!rd_active); 					// 읽기 유휴 시 AR 수락
	assign axi.awready = (!wr_active) && !bvalid_reg; 	// 쓰기 유휴/응답없음 시 AW 수락
	assign axi.wready = wr_active; 						// WR 진행 중에만 데이터 수락
  
	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin // 클록/리셋
      	if (!axi.aresetn) begin 				// 비동기 리셋
          	for (int i=0; i<64; i++) 
				mem[i] <= 32'hCAFE_0000 + i; 	// 초기 패턴
			for (int j=64; j<1024; j++)
              	mem[j] <= 32'h0; 				// 나머지 0
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
					bresp_reg <= 2'b00;						 // OKAY
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
