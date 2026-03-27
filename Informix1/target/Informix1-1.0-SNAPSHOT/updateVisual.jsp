<%@page import="java.sql.*"%>
<%@page contentType="text/plain; charset=UTF-8" pageEncoding="UTF-8"%>

<%
request.setCharacterEncoding("UTF-8");

String asunto = request.getParameter("asunto");
String solucion = request.getParameter("solucion");
String fecha = request.getParameter("fecha");
String value = request.getParameter("value");

if (asunto == null || solucion == null || fecha == null || value == null) {
    out.print("ERROR");
    return;
}

try {
    Class.forName("com.informix.jdbc.IfxDriver");

    Connection cn = DriverManager.getConnection(
        "jdbc:informix-sqli://10.35.240.15:1527/inf:INFORMIXSERVER=hbar4hu",
        "informix", "w40inf"
    );

    PreparedStatement ps = cn.prepareStatement(
        "UPDATE ctl.solinf1 " +
        "SET visual = ? " +
        "WHERE TRIM(asunto) = ? " +
        "AND TRIM(solucion) = ? " +
        "AND TO_CHAR(fecha, '%d-%m-%Y') = ?"
    );

    ps.setInt(1, Integer.parseInt(value));
    ps.setString(2, asunto);
    ps.setString(3, solucion);
    ps.setString(4, fecha);

    int updated = ps.executeUpdate();

    ps.close();
    cn.close();

    out.print(updated > 0 ? "OK" : "ERROR");

} catch (Exception e) {
    out.print("ERROR");
}
%>
