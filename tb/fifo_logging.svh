//=============================================================================
// Header: fifo_logging.svh
// Description: Reusable procedural logging tasks for Icarus Verilog 11/12/13.
// Note: Intentionally no `ifndef guard so each module declares its own tasks.
//=============================================================================

task automatic log_info(input string msg);
    $display("[INFO]  [%0t ns] %s", $time, msg);
endtask

task automatic log_warn(input string msg);
    $display("[WARN]  [%0t ns] %s", $time, msg);
endtask

task automatic log_error(input string msg);
    pkg_error_count++;
    $display("*** ERROR: [%0t ns] %s", $time, msg);
endtask

task automatic log_fatal(input string msg);
    pkg_error_count++;
    $display("*** FATAL: [%0t ns] %s", $time, msg);
endtask
