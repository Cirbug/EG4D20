<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="D:/2026fpga/EG4D20">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.168116</TD_Version>
    <Name>EG4D20_CNN_DIGIT</Name>
    <HardWare>
        <Family>EG4</Family>
        <Device>EG4D20EG176</Device>
        <Speed></Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="uisrc/01_rtl/cnn_digit_infer.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File>
            <File Path="cnn/exports/eg4d20_digit_int8_20261026_v2/cnn_digit_params.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File>
        </Verilog>
        <SDC_FILE>
            <File Path="uisrc/04_pin/cnn_digit_timing.sdc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="constraint_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File>
        </SDC_FILE>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles"></FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles"></FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL></LABEL>
        <MODULE>cnn_digit_infer</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property></Property>
    <Device_Settings></Device_Settings>
    <Configurations></Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy"></Strategy>
            <UserParams></UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy"></Strategy>
            <UserParams></UserParams>
        </Run>
    </Runs>
    <Project_Settings></Project_Settings>
</Project>
