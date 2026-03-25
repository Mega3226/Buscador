<%@page import="java.sql.*"%>
<%@page contentType="text/html" pageEncoding="UTF-8"%>

<!DOCTYPE html>
<html>
<head>
    <title>Detalle de incidencia</title>
</head>
<body>

<%
String id = request.getParameter("id");

if (id != null) {

    Class.forName("com.informix.jdbc.IfxDriver");

    Connection cn = DriverManager.getConnection(
        "jdbc:informix-sqli://10.35.240.15:1527/inf:INFORMIXSERVER=hbar4hu",
        "informix",
        "w40inf"
    );

    PreparedStatement ps = cn.prepareStatement(
        "SELECT * FROM ctl.solinf1 WHERE id_hard = ?"
    );
    ps.setInt(1, Integer.parseInt(id));

    ResultSet rs = ps.executeQuery();

    if (rs.next()) {
%>

<h2>Detalle de incidencia</h2>

<p><b>ID:</b> <%=rs.getInt("id_hard")%></p>
<p><b>Asunto:</b> <%=rs.getString("tt")%></p>
<p><b>Fecha:</b> <%=rs.getString("tiempo")%></p>
<p><b>Aplicación:</b> <%=rs.getString("aplicacion")%></p>
<p><b>Registrado por:</b> <%=rs.getString("guarda")%></p>
<p><b>Teléfono:</b> <%=rs.getString("tel")%></p>

<h3>Solución:</h3>
<p><%=rs.getString("solucion")%></p>

<%
    } else {
%>
<p>No se encontró la incidencia.</p>
<%
    }

    rs.close();
    ps.close();
    cn.close();
}
%>

<br><br>
<a href="buscador.jsp">Volver al buscador</a>

</body>
</html>
