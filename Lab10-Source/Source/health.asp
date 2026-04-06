<%@ Language=VBScript %>
<%
    Response.Status = "200 OK"
    Response.ContentType = "application/json"
%>
{
  "status": "healthy",
  "server": "<%=CreateObject("WScript.Network").ComputerName%>",
  "timestamp": "<%=Now()%>"
}
