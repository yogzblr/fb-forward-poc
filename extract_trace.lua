function extract_trace_context(tag, timestamp, record)
    -- Debug: Mark that filter ran
    record["lua_filter_applied"] = "yes"
    
    -- Helper function to convert binary string to hex
    local function bin_to_hex(bin_str)
        if type(bin_str) ~= "string" then
            return nil
        end
        if #bin_str == 0 then
            return nil
        end
        local hex_str = ""
        local success, result = pcall(function()
            for i = 1, #bin_str do
                local byte_val = string.byte(bin_str, i)
                hex_str = hex_str .. string.format("%02x", byte_val)
            end
            return hex_str
        end)
        if success then
            return result
        else
            return nil
        end
    end
    
    -- Try to extract trace_id and span_id from OTLP metadata
    if record["__internal__"] ~= nil then
        local log_metadata = record["__internal__"]["log_metadata"]
        if log_metadata ~= nil and log_metadata["otlp"] ~= nil then
            local otlp = log_metadata["otlp"]
            
            -- Extract and convert trace_id (16 bytes = 128 bits)
            if otlp["trace_id"] ~= nil then
                local trace_id_bin = otlp["trace_id"]
                local trace_id_type = type(trace_id_bin)
                if trace_id_type == "string" and #trace_id_bin > 0 then
                    local hex_result = bin_to_hex(trace_id_bin)
                    if hex_result ~= nil then
                        record["trace_id"] = hex_result
                    end
                elseif trace_id_type == "string" then
                    -- Empty string, skip
                end
            end
            
            -- Extract and convert span_id (8 bytes = 64 bits)
            if otlp["span_id"] ~= nil then
                local span_id_bin = otlp["span_id"]
                local span_id_type = type(span_id_bin)
                if span_id_type == "string" and #span_id_bin > 0 then
                    local hex_result = bin_to_hex(span_id_bin)
                    if hex_result ~= nil then
                        record["span_id"] = hex_result
                    end
                elseif span_id_type == "string" then
                    -- Empty string, skip
                end
            end
            
            -- Extract trace_flags
            if otlp["trace_flags"] ~= nil then
                record["trace_flags"] = otlp["trace_flags"]
            end
            
            -- Extract severity
            if otlp["severity_text"] ~= nil then
                record["severity"] = otlp["severity_text"]
            end
        end
        
        -- Extract service name from resource attributes
        local group_attrs = record["__internal__"]["group_attributes"]
        if group_attrs ~= nil and group_attrs["resource"] ~= nil then
            local resource = group_attrs["resource"]
            if resource["attributes"] ~= nil then
                local attrs = resource["attributes"]
                if attrs["service.name"] ~= nil then
                    record["service_name"] = attrs["service.name"]
                end
            end
        end
    end
    
    return 2, timestamp, record
end
