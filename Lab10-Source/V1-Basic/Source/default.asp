<%@ Language=VBScript CodePage=65001 %>
<%
    ' --- LOGIKA ---
    Response.CharSet = "UTF-8"
    Dim randNum
    Randomize 
    randNum = Int((999 - 100 + 1) * Rnd + 100)

    Dim fso, logFile, logPath, fileName, serverName, clientIP
    Set wshNetwork = Server.CreateObject("WScript.Network")
    serverName = wshNetwork.ComputerName

    Dim testIP
    testIP = Request.ServerVariables("HTTP_X_TEST_IP")
    
    If testIP <> "" Then
        clientIP = testIP
    Else
        clientIP = Request.ServerVariables("REMOTE_ADDR")
    End If

    fileName = "log-" & Year(Now) & Right("0" & Month(Now),2) & Right("0" & Day(Now),2) & "-" & Right("0" & Hour(Now),2) & Right("0" & Minute(Now),2) & Right("0" & Second(Now),2) & "-" & randNum & ".txt"
    logPath = "C:\mounts\logs\" & fileName
    
    On Error Resume Next
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    Set logFile = fso.CreateTextFile(logPath, True)
    
    If Err.Number <> 0 Then
        Response.Write "Log Error: " & Err.Description
        Err.Clear
    Else
        logFile.WriteLine("{")
        logFile.WriteLine("  ""timestamp"": """ & Now() & """,")
        logFile.WriteLine("  ""ip"": """ & clientIP & """,")
        logFile.WriteLine("  ""server"": """ & serverName & """,")
        logFile.WriteLine("  ""status"": ""OK""")
        logFile.WriteLine("}")
        logFile.Close
    End If
    On Error Goto 0
%>
<!DOCTYPE html>
<html lang="lt">
<head>
    <meta charset="UTF-8">
    <title>Lankytojų Seklys v1</title>
</head>
<body style="font-family: Consolas, monospace; padding: 20px;">

    <h3><VARDAS> 🕵️‍♂️ LANKYTOJŲ SEKLYS v1</h3>
    <hr>
    
    <p><strong>STATUSAS:</strong> <span style="color:green">VEIKIA</span></p>
    
    <p>
        Failas: <%=fileName%><br>
        Laikas: <%=Now()%><br>
        IP: <%=clientIP%>
    </p>

    <hr>

</body>
</html>
