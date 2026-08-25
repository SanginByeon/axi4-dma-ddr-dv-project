// ============================================================================
// dma_tx.sv - DMA Transaction
//
// - DMA source/destination address, transfer size, CTRL 및 DDR model 검증 설정을 정의.
// - 전송 크기에 맞춰 source memory preload용 payload pattern을 생성.
// - 4-byte 주소 정렬, 4KB memory 범위 및 source/destination 비중첩을 제한.
// - Factory 등록, 정상 전송 기본값 및 transaction 출력 형식을 제공.
// ============================================================================

class dma_tx extends uvm_sequence_item;
    rand bit [31:0] src_addr;      // 소스 주소
    rand bit [31:0] dst_addr;      // 목적지 주소
    rand bit [31:0] size;          // 전송 크기
    rand byte data_payload[];      // 데이터 무결성 검증용 데이터

    // CTRL 레지스터 하위 3개 비트
    rand bit enable;
    rand bit start;
    rand bit irq;

    // DDR memory model의 AXI4 W channel backpressure 발생 확률
    rand bit [7:0] backpressure_prob;

    // DDR memory model의 BRESP 오류 주입 설정
    rand bit error_inject;

    // Sequence별 테스트 시나리오 이름
    string scenario_name;

    function new(input string name = "dma_tx");
        super.new(name);
    endfunction

    // [Factory registration]
    `uvm_object_utils_begin(dma_tx)
        `uvm_field_int(src_addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(dst_addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(size, UVM_DEFAULT | UVM_DEC)
        `uvm_field_int(enable, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(start, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(irq, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(backpressure_prob, UVM_DEFAULT | UVM_DEC)
        `uvm_field_int(error_inject, UVM_DEFAULT | UVM_BIN)
        `uvm_field_array_int(data_payload, UVM_DEFAULT)
        `uvm_field_string(scenario_name, UVM_DEFAULT)
    `uvm_object_utils_end

    // [Address constraint] : DUT가 지원하는 4-byte aligned address로 제한
    constraint c_addr_alignment {
        src_addr[1:0] == 2'b00;
        dst_addr[1:0] == 2'b00;
    }

    // [Default constraint] : 기본적으로 4~1024-byte 정상 전송 생성
    constraint c_default_transfer {
        soft size inside {[4:1024]};
        soft size[1:0] == 2'b00;

        soft enable == 1'b1;
        soft start  == 1'b1;
        soft irq    == 1'b1;
    }

    // [Backpressure constraint] : 기본 동작은 stall 없이 유지하고 최대값은 99%로 제한
    constraint c_backpressure {
        backpressure_prob inside {[0:99]};
        soft backpressure_prob == 0;
    }

    // [Error injection constraint] : 정상 전송에서는 BRESP 오류를 주입하지 않음
    constraint c_error_injection {
        soft error_inject == 1'b0;
    }

    // [Memory constraint] : Source/Destination 전송 영역을 4KB memory 내부로 제한
    constraint c_memory_range {
        size inside {[1:2048]};

        src_addr <= 32'd4096 - size;
        dst_addr <= 32'd4096 - size;
    }

    // [Overlap constraint] : Source와 Destination 전송 영역의 중첩 방지
    constraint c_no_overlap {
        (src_addr + size <= dst_addr) ||
        (dst_addr + size <= src_addr);
    }

    // [Payload constraint] : 전송 크기에 맞춰 source preload용 배열 크기 결정
    constraint c_data_size {
        data_payload.size() == size;
    }

    // [Transaction formatting] : Scenario와 transaction 정보를 구분하여 출력
    virtual function string convert2string();
        string s = super.convert2string();

        // Sequence/Driver의 원본 transaction에만 존재하는 Scenario 이름 표시
        if (scenario_name != "")
            s = {s, $sformatf("[Scenario: %s] ", scenario_name)};

        s = {s, "[Transaction: "};
        s = {s, $sformatf("src_addr:0x%0h, ", src_addr)};
        s = {s, $sformatf("dst_addr:0x%0h, ", dst_addr)};
        s = {s, $sformatf("size:%0d, ", size)};
        s = {s, $sformatf("enable:%0b, ", enable)};
        s = {s, $sformatf("start:%0b, ", start)};
        s = {s, $sformatf("irq:%0b, ", irq)};
        s = {s, $sformatf("backpressure_prob:%0d%%, ", backpressure_prob)};
        s = {s, $sformatf("error_inject:%0b]", error_inject)};

        return s;
    endfunction

    // [Payload generation] : src_addr부터 source memory에 preload할 pattern 생성
    // 실제 memory 초기화는 Sequence의 preload_src_mem()에서 수행
    function void post_randomize();
        for (int i = 0; i < data_payload.size(); i += 4) begin
            int word = 32'hCAFE_0000 + (i / 4);

            if (i < data_payload.size())
                data_payload[i] = word[7:0];
            if (i + 1 < data_payload.size())
                data_payload[i + 1] = word[15:8];
            if (i + 2 < data_payload.size())
                data_payload[i + 2] = word[23:16];
            if (i + 3 < data_payload.size())
                data_payload[i + 3] = word[31:24];
        end
    endfunction
endclass
