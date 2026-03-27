<%@page import="java.sql.*"%>
<%@page import="java.text.Normalizer"%>
<%@page import="java.util.*"%>
<%@page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
response.setContentType("text/html; charset=UTF-8");
%>

<%!
// ==================== CLASE ROW ====================
private class Row {
    public String fecha;
    public String asunto;
    public String solucion;
    public int visual;
    public Set<String> keys = new LinkedHashSet<>();
}

// ==================== MÉTODOS AUXILIARES ====================
private String escapeHtml(String s) {
    if (s == null) return "";
    return s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&#39;");
}

private String normalize(String s) {
    if (s == null) return "";
    return Normalizer.normalize(s, Normalizer.Form.NFD)
            .replaceAll("\\p{M}", "")
            .toLowerCase()
            .replaceAll("[^a-z0-9 ]", " ")
            .replaceAll("\\s+", " ")
            .trim();
}

private int scoreEncoding(String s) {
    if (s == null) return Integer.MIN_VALUE;
    int score = 0;
    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        if (c == '\uFFFD') score -= 5;
        else if (c == 'Ã') score -= 2;
        else if (c >= 32 && c <= 126) score++;
        else if (c >= 160) score += 2;
    }
    return score;
}

private String fixEncoding(String s) {
    if (s == null) return null;
    String best = s;
    int bestScore = scoreEncoding(s);

    try {
        String c1 = new String(s.getBytes("ISO-8859-1"), "UTF-8");
        int sc1 = scoreEncoding(c1);
        if (sc1 > bestScore) {
            best = c1;
            bestScore = sc1;
        }
    } catch (Exception ignored) {}

    try {
        String c2 = new String(s.getBytes("UTF-8"), "ISO-8859-1");
        int sc2 = scoreEncoding(c2);
        if (sc2 > bestScore) {
            best = c2;
            bestScore = sc2;
        }
    } catch (Exception ignored) {}

    return best;
}

private boolean matchesWholeWord(String text, String word) {
    if (text == null || word == null) return false;
    String t = normalize(text);
    String w = normalize(word);
    return (" " + t + " ").contains(" " + w + " ");
}

private boolean matchesPhrase(String text, String phrase) {
    if (text == null || phrase == null) return false;
    String t = normalize(text);
    String p = normalize(phrase);
    for (String w : p.split(" ")) {
        if (w.isEmpty()) continue;
        if (!t.contains(w)) return false;
    }
    return true;
}

private class NormMap {
    public String normText;
    public int[] normToOrig;
}

private NormMap buildNormMap(String original) {
    NormMap nm = new NormMap();
    if (original == null) {
        nm.normText = "";
        nm.normToOrig = new int[0];
        return nm;
    }

    StringBuilder normBuilder = new StringBuilder();
    List<Integer> indexMap = new ArrayList<>();

    for (int i = 0; i < original.length(); i++) {
        char c = original.charAt(i);
        String s = String.valueOf(c);
        String nfd = Normalizer.normalize(s, Normalizer.Form.NFD);
        for (int j = 0; j < nfd.length(); j++) {
            char nc = nfd.charAt(j);
            if (Character.getType(nc) == Character.NON_SPACING_MARK) {
                continue;
            }
            normBuilder.append(Character.toLowerCase(nc));
            indexMap.add(i);
        }
    }

    nm.normText = normBuilder.toString();
    nm.normToOrig = new int[indexMap.size()];
    for (int i = 0; i < indexMap.size(); i++) {
        nm.normToOrig[i] = indexMap.get(i);
    }
    return nm;
}

private String highlightTerms(String text, List<String> terms) {
    if (text == null) return "";
    if (terms == null || terms.isEmpty()) return escapeHtml(text);

    NormMap nm = buildNormMap(text);
    String normText = nm.normText;
    int[] map = nm.normToOrig;

    class HighlightRange {
        int start, end;
        HighlightRange(int s, int e) { this.start = s; this.end = e; }
    }
    
    List<HighlightRange> ranges = new ArrayList<>();

    for (String term : terms) {
        if (term == null) continue;
        term = term.trim();
        if (term.isEmpty()) continue;

        String normTerm = normalize(term);
        if (normTerm.isEmpty()) continue;

        boolean isSingleWord = !normTerm.contains(" ");

        if (isSingleWord) {
            String patternStr = "\\b" + java.util.regex.Pattern.quote(normTerm) + "\\b";
            java.util.regex.Pattern pattern = java.util.regex.Pattern.compile(patternStr);
            java.util.regex.Matcher m = pattern.matcher(normText);
            while (m.find()) {
                int ns = m.start();
                int ne = m.end();
                if (ns >= 0 && ne <= map.length) {
                    int os = map[ns];
                    int oe = map[ne - 1] + 1;
                    ranges.add(new HighlightRange(os, oe));
                }
            }
        } else {
            int from = 0;
            while (true) {
                int idx = normText.indexOf(normTerm, from);
                if (idx == -1) break;
                int ns = idx;
                int ne = idx + normTerm.length();
                if (ns >= 0 && ne <= map.length) {
                    int os = map[ns];
                    int oe = map[ne - 1] + 1;
                    ranges.add(new HighlightRange(os, oe));
                }
                from = idx + normTerm.length();
            }
        }
    }

    if (ranges.isEmpty()) return escapeHtml(text);

    ranges.sort((a, b) -> Integer.compare(a.start, b.start));
    List<HighlightRange> merged = new ArrayList<>();
    HighlightRange cur = ranges.get(0);
    for (int i = 1; i < ranges.size(); i++) {
        HighlightRange r = ranges.get(i);
        if (r.start <= cur.end) {
            cur.end = Math.max(cur.end, r.end);
        } else {
            merged.add(cur);
            cur = r;
        }
    }
    merged.add(cur);

    StringBuilder out = new StringBuilder();
    int pos = 0;
    for (HighlightRange r : merged) {
        if (r.start > pos) out.append(escapeHtml(text.substring(pos, r.start)));
        out.append("<span class='highlight'>");
        out.append(escapeHtml(text.substring(r.start, r.end)));
        out.append("</span>");
        pos = r.end;
    }
    if (pos < text.length()) out.append(escapeHtml(text.substring(pos)));

    return out.toString();
}

private List<Row> paginateRows(List<Row> rows, int pageNum, int pageSize) {
    int totalRows = rows.size();
    int startIdx = (pageNum - 1) * pageSize;
    int endIdx = Math.min(startIdx + pageSize, totalRows);
    
    if (startIdx >= totalRows) startIdx = 0;
    if (startIdx < 0) startIdx = 0;
    
    return rows.subList(startIdx, endIdx);
}
%>

<%
String q = request.getParameter("q");
String orden = request.getParameter("orden");
if (orden == null || !(orden.equals("ASC") || orden.equals("DESC"))) orden = "DESC";

String[] modulabSelected = request.getParameterValues("modulab[]");

String pageNumStr = request.getParameter("pageNum");
int pageNum = 1;
if (pageNumStr != null) {
    try {
        pageNum = Integer.parseInt(pageNumStr);
        if (pageNum < 1) pageNum = 1;
    } catch (Exception e) { pageNum = 1; }
}

boolean hasText = (q != null && !q.trim().isEmpty());
boolean hasApps = (modulabSelected != null && modulabSelected.length > 0);
boolean hasSearch = hasText || hasApps;

List<Map<String,String>> aplicacionesList = new ArrayList<>();
Map<String,List<String>> appToWords = new LinkedHashMap<>();

try {
    Class.forName("com.informix.jdbc.IfxDriver");
    Connection cnA = DriverManager.getConnection(
        "jdbc:informix-sqli://10.35.240.15:1527/clihis:INFORMIXSERVER=hbar4hu",
        "informix","w40inf"
    );

    PreparedStatement psA = cnA.prepareStatement(
        "SELECT aplicacion, rastro FROM inc_aplicaciones ORDER BY aplicacion"
    );

    ResultSet rsA = psA.executeQuery();

    while (rsA.next()) {
        String appName = fixEncoding(rsA.getString("aplicacion"));
        String rastro = fixEncoding(rsA.getString("rastro"));

        Map<String,String> m = new HashMap<>();
        m.put("aplicacion", appName);
        m.put("rastro", rastro);
        aplicacionesList.add(m);

        List<String> words = new ArrayList<>();
        if (appName != null && !appName.trim().isEmpty()) words.add(appName);

        if (rastro != null && !rastro.trim().isEmpty()) {
            for (String w : rastro.split(",")) {
                w = w.trim();
                if (!w.isEmpty()) words.add(w);
            }
        }

        appToWords.put(appName, words);
    }

    rsA.close();
    psA.close();
    cnA.close();

} catch (Exception e) {
    out.println("<div style='color:red;font-weight:bold;'>Error cargando inc_aplicaciones: "
        + escapeHtml(e.getMessage()) + "</div>");
}

List<Row> rows = new ArrayList<>();

Map<String,Integer> searchCounts = new LinkedHashMap<>();
Map<String,Integer> appCounts = new LinkedHashMap<>();
Map<String,Integer> rastroCounts = new LinkedHashMap<>();
Map<String,String> displayLabel = new LinkedHashMap<>();

if (hasText) {
    String k = normalize(q);
    searchCounts.put(k, 0);
    displayLabel.put(k, q);
}

if (hasApps) {
    for (String appName : modulabSelected) {
        String appNorm = normalize(appName);
        appCounts.put(appNorm, 0);
        displayLabel.put(appNorm, appName);

        List<String> words = appToWords.get(appName);
        if (words != null) {
            for (String w : words) {
                String wn = normalize(w);
                rastroCounts.put(wn, 0);
                displayLabel.put(wn, w);
            }
        }
    }
}

try {
    Class.forName("com.informix.jdbc.IfxDriver");
    Connection cn = DriverManager.getConnection(
        "jdbc:informix-sqli://10.35.240.15:1527/inf:INFORMIXSERVER=hbar4hu",
        "informix","w40inf"
    );

    StringBuilder sql = new StringBuilder();
    List<String> params = new ArrayList<>();

    if (hasSearch) {
        sql.append("SELECT asunto, solucion, fecha, visual, ");
        sql.append("TO_CHAR(fecha,'%d-%m-%Y') AS fecha_formateada ");
        sql.append("FROM ctl.solinf1 ");
        sql.append("WHERE (");

        // ============ BÚSQUEDA COMBINADA: TEXTO Y APLICACIONES ============
        List<String> conditions = new ArrayList<>();

        // Condición 1: Búsqueda de texto
        if (hasText) {
            conditions.add("(LOWER(asunto) LIKE ? OR LOWER(solucion) LIKE ?)");
            String p = "%" + q.toLowerCase() + "%";
            params.add(p);
            params.add(p);
        }

        // Condición 2: Búsqueda de aplicaciones (nombre + rastro)
        if (hasApps) {
            List<String> allWords = new ArrayList<>();
            for (String appName : modulabSelected) {
                List<String> ws = appToWords.get(appName);
                if (ws != null) {
                    for (String w : ws) {
                        w = w.trim();
                        if (!w.isEmpty()) allWords.add(w.toLowerCase());
                    }
                }
            }

            if (!allWords.isEmpty()) {
                StringBuilder appCondition = new StringBuilder("(");
                boolean first = true;
                for (String w : allWords) {
                    if (!first) appCondition.append(" OR ");
                    appCondition.append("LOWER(asunto) LIKE ? OR LOWER(solucion) LIKE ?");
                    String p = "%" + w + "%";
                    params.add(p);
                    params.add(p);
                    first = false;
                }
                appCondition.append(")");
                conditions.add(appCondition.toString());
            }
        }

        // Unir todas las condiciones con OR
        boolean first = true;
        for (String condition : conditions) {
            if (!first) sql.append(" OR ");
            sql.append(condition);
            first = false;
        }

        sql.append(") ORDER BY fecha ").append(orden);

    } else {
        sql.append("SELECT FIRST 5 asunto, solucion, fecha, visual, ");
        sql.append("TO_CHAR(fecha,'%d-%m-%Y') AS fecha_formateada ");
        sql.append("FROM ctl.solinf1 ORDER BY fecha DESC");
    }

    PreparedStatement ps = cn.prepareStatement(sql.toString());
    int idx = 1;
    for (String p : params) ps.setString(idx++, p);

    ResultSet rs = ps.executeQuery();

    while (rs.next()) {
        Row r = new Row();
        r.fecha = rs.getString("fecha_formateada");
        r.asunto = fixEncoding(rs.getString("asunto"));
        r.solucion = fixEncoding(rs.getString("solucion"));
        r.visual = rs.getInt("visual");

        if (hasText) {
            boolean matchText;
            if (q.contains(" ")) {
                matchText = matchesPhrase(r.asunto, q) || matchesPhrase(r.solucion, q);
            } else {
                matchText = matchesWholeWord(r.asunto, q) || matchesWholeWord(r.solucion, q);
            }
            if (matchText) {
                String keyNorm = normalize(q);
                if (searchCounts.containsKey(keyNorm) && !r.keys.contains(keyNorm)) {
                    searchCounts.put(keyNorm, searchCounts.get(keyNorm) + 1);
                    r.keys.add(keyNorm);
                }
            }
        }

        if (hasApps) {
            for (String appName : modulabSelected) {
                List<String> words = appToWords.get(appName);
                if (words == null) continue;

                boolean rowMatchesApp = false;

                for (String w : words) {
                    if (matchesWholeWord(r.asunto, w) || matchesWholeWord(r.solucion, w)) {
                        rowMatchesApp = true;
                        String wn = normalize(w);
                        if (rastroCounts.containsKey(wn) && !r.keys.contains(wn)) {
                            rastroCounts.put(wn, rastroCounts.get(wn) + 1);
                            r.keys.add(wn);
                        }
                    }
                }

                if (rowMatchesApp) {
                    String appNorm = normalize(appName);
                    if (appCounts.containsKey(appNorm) && !r.keys.contains(appNorm)) {
                        appCounts.put(appNorm, appCounts.get(appNorm) + 1);
                        r.keys.add(appNorm);
                    }
                }
            }
        }

        rows.add(r);
    }

    rs.close();
    ps.close();
    cn.close();

} catch (Exception e) {
    out.println("<div style='color:red;font-weight:bold;'>Error cargando incidencias: "
        + escapeHtml(e.getMessage()) + "</div>");
}

rows.sort((a, b) -> {
    boolean aFav = (a.visual == 3);
    boolean bFav = (b.visual == 3);
    if (aFav && !bFav) return -1;
    if (!aFav && bFav) return 1;
    return 0;
});

int ocultasCount = 0;
for (Row r : rows) if (r.visual == 1) ocultasCount++;

int pageSize = 250;
int totalPages = (rows.size() + pageSize - 1) / pageSize;
if (pageNum > totalPages && totalPages > 0) pageNum = totalPages;

List<Row> paginatedRows = new ArrayList<>();
if (!hasSearch) {
    paginatedRows = rows;
} else {
    paginatedRows = paginateRows(rows, pageNum, pageSize);
}
%>

<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Buscar incidencia</title>
<meta name="viewport" content="width=device-width, initial-scale=1">

<style>
* {
    box-sizing: border-box;
}

body {
    margin: 0;
    font-family: "Segoe UI", Arial, sans-serif;
    background: #f1f4f8;
    color: #0b2540;
    padding: 20px;
}

.container {
    max-width: 1300px;
    margin: 0 auto;
}

.header {
    display: flex;
    align-items: center;
    gap: 20px;
    justify-content: center;
    margin-bottom: 10px;
}

.header img {
    height: 80px;
    border-radius: 6px;
}

.header h1 {
    margin: 0;
    font-size: 28px;
    color: #0057A8;
    font-weight: 700;
}

.card {
    background: #ffffff;
    padding: 28px;
    border-radius: 10px;
    border: 1px solid #d6dce5;
    box-shadow: 0 4px 18px rgba(0,0,0,0.08);
    min-height: 480px;
}

.top-row {
    display: flex;
    justify-content: center;
    margin-bottom: 10px;
}

.input-wrap {
    width: 100%;
    max-width: 950px;
    display: flex;
    gap: 10px;
}

input[type=text] {
    flex: 1;
    padding: 12px;
    border-radius: 6px;
    border: 1px solid #b8c4d1;
    font-size: 16px;
}

input[type=text]:focus {
    outline: none;
    border-color: #0057A8;
    box-shadow: 0 0 5px rgba(0,87,168,0.3);
}

.btn-buscar {
    padding: 10px 18px;
    border: none;
    border-radius: 6px;
    background: #0057A8;
    color: white;
    font-weight: bold;
    cursor: pointer;
    transition: 0.2s;
}

.btn-buscar:hover {
    background: #004a90;
}

.btn-modulab {
    background: #FFD84D;
    color: #000;
    padding: 10px 16px;
    border-radius: 6px;
    border: none;
    font-weight: bold;
    cursor: pointer;
    transition: 0.2s;
}

.btn-modulab:hover {
    background: #FFC700;
}

.modulab-dropdown {
    position: relative;
}

.modulab-options {
    display: none;
    position: absolute;
    background: #fff;
    padding: 12px 16px;
    border-radius: 10px;
    border: 1px solid #d0d0d0;
    box-shadow: 0 4px 20px rgba(0,0,0,0.15);
    margin-top: 6px;
    z-index: 999;
    width: 260px;
    max-height: 350px;
    overflow-y: auto;
}

.modulab-options label {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 4px 0;
    font-size: 13px;
    cursor: pointer;
}

.modulab-options label:hover {
    background: #f0f0f0;
    border-radius: 4px;
    padding: 4px 8px;
}

.modulab-options input[type="checkbox"] {
    cursor: pointer;
}

.small-note {
    margin-top: 8px;
    color: #555;
    font-size: 13px;
}

.found-words {
    margin-top: 20px;
}

.found-row {
    margin-bottom: 12px;
}

.found-row strong {
    display: block;
    margin-bottom: 6px;
    font-size: 15px;
    color: #0057A8;
}

.word-box-container {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
}

.word-box {
    display: flex;
    align-items: center;
    gap: 8px;
    background: #ffffff;
    border: 1px solid #d0d0d0;
    padding: 6px 10px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
    transition: 0.2s;
    user-select: none;
}

.word-box:hover {
    border-color: #0057A8;
    box-shadow: 0 2px 8px rgba(0,87,168,0.1);
}

.word-box.active-filter {
    border-color: #0057A8;
    background: #e3f2fd;
    font-weight: bold;
}

.word-circle {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #4CAF50;
    flex-shrink: 0;
    transition: 0.2s;
}

.word-circle.off {
    background: #e53935;
}

#resetFiltersBtn {
    margin-top: 6px;
    padding: 6px 12px;
    border-radius: 6px;
    border: 1px solid #b8c4d1;
    background: #ffffff;
    cursor: pointer;
    font-size: 13px;
    transition: 0.2s;
}

#resetFiltersBtn:hover {
    background: #e3f2fd;
    border-color: #0057A8;
}

.filter-visual {
    margin-top: 15px;
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
}

.vis-btn {
    padding: 8px 12px;
    border-radius: 6px;
    border: none;
    font-weight: bold;
    cursor: pointer;
    font-size: 13px;
    transition: 0.2s;
}

.vis-btn.green {
    background: #c8e6c9;
}

.vis-btn.red {
    background: #ffcdd2;
}

.vis-btn.fav {
    background: #ffe082;
}

.vis-btn.active {
    outline: 2px solid #000;
}

.vis-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
}

.table-wrap {
    margin-top: 15px;
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    border: 1px solid #d6dce5;
    table-layout: fixed;
}

thead th {
    background: #0057A8;
    color: white;
    padding: 8px;
    text-align: center;
    font-weight: 600;
}

thead th select {
    padding: 4px;
    border-radius: 4px;
    border: 1px solid #999;
    background: white;
    color: #000;
    cursor: pointer;
}

td {
    padding: 8px 10px;
    border-bottom: 1px solid #e5e9ef;
    vertical-align: top;
    word-wrap: break-word;
    overflow-wrap: break-word;
}

th.col-fecha, td.col-fecha {
    width: 110px;
}

th.col-visual, td.col-visual {
    width: 90px;
}

.highlight {
    background: yellow;
    font-weight: bold;
}

.col-fecha {
    text-align: center;
    white-space: nowrap;
}

.col-visual {
    text-align: center;
}

.circle {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    cursor: pointer;
    margin: 0 auto 4px;
    transition: 0.2s;
}

.circle:hover {
    transform: scale(1.2);
}

.circle.green {
    background: #4CAF50;
}

.circle.red {
    background: #e53935;
}

.star {
    cursor: pointer;
    font-size: 18px;
    margin-top: 4px;
    color: #bbb;
    transition: 0.2s;
}

.star:hover {
    transform: scale(1.2);
    color: #ffca28;
}

.fav-star {
    color: #ffca28;
}

tr.favorito {
    background: #fff8d6 !important;
}

tr.favorito .highlight {
    background: #ff9800 !important;
}

tbody tr:hover {
    background: #f5f7fa;
}

.pagination {
    margin-top: 30px;
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
}

.pagination button {
    padding: 10px 16px;
    border-radius: 6px;
    border: 1px solid #b8c4d1;
    background: #ffffff;
    cursor: pointer;
    font-weight: bold;
    transition: 0.2s;
    min-width: 120px;
}

.pagination button:hover:not(:disabled) {
    background: #e3f2fd;
    border-color: #0057A8;
    transform: translateY(-2px);
}

.pagination button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    color: #999;
}

.pagination-info {
    min-width: 180px;
    text-align: center;
    font-weight: bold;
    font-size: 14px;
}

@media (max-width: 768px) {
    .header {
        flex-direction: column;
        gap: 10px;
    }

    .input-wrap {
        flex-direction: column;
    }

    .word-box-container {
        flex-direction: column;
    }

    .pagination {
        gap: 5px;
    }

    .pagination button {
        padding: 8px 12px;
        font-size: 12px;
        min-width: auto;
    }
}
</style>
</head>

<body>

<div class="container">

    <div class="header">
        <img src="File/Image/salud-sin-info.jpg" alt="Salud">
        <h1>Buscar incidencia</h1>
    </div>

    <div class="card">

        <form id="buscadorForm" method="GET" action="buscador.jsp">
            <div class="top-row">
                <div class="input-wrap">
                    <input type="text" name="q" id="q" placeholder="Busca tu incidencia"
                           value="<%= q != null ? escapeHtml(q) : "" %>">

                    <div class="modulab-dropdown">
                        <button type="button" class="btn-modulab" onclick="toggleModulabSelect()">
                            Aplicaciones ▼
                        </button>

                        <div id="modulabSelect" class="modulab-options">
                            <label><input type="checkbox" id="modulabAll" onchange="toggleModulabAll()"> Todas</label>

                            <% for (Map<String,String> appRow : aplicacionesList) {
                                String appName = appRow.get("aplicacion");
                                boolean checked = false;
                                if (modulabSelected != null) {
                                    for (String s : modulabSelected) {
                                        if (s.equals(appName)) { checked = true; break; }
                                    }
                                }
                            %>
                            <label>
                                <input type="checkbox" name="modulab[]" value="<%= escapeHtml(appName) %>"
                                       <%= checked ? "checked" : "" %> >
                                <%= escapeHtml(appName) %>
                            </label>
                            <% } %>
                        </div>
                    </div>

                    <button type="submit" class="btn-buscar">Buscar</button>
                </div>
            </div>

            <input type="hidden" name="orden" id="ordenInput" value="<%=orden%>">
            <input type="hidden" name="pageNum" id="pageNumInput" value="<%= pageNum %>">
        </form>

        <div class="small-note">
            Selecciona aplicaciones si quieres incluirlas en la búsqueda (se usarán el nombre y su rastro).
        </div>

        <% if (hasSearch && !rows.isEmpty()) { %>

        <div class="found-words">

            <div class="found-row">
                <strong>Palabra o frase buscada</strong>
                <div class="word-box-container">
                    <% for (Map.Entry<String,Integer> e : searchCounts.entrySet()) {
                        if (e.getValue() > 0) { %>
                    <div class="word-box search-word"
                         data-key="<%= escapeHtml(displayLabel.get(e.getKey())) %>"
                         data-visibility="true">
                        <div class="word-circle"></div>
                        <span><%= escapeHtml(displayLabel.get(e.getKey())) %> (<%=e.getValue()%>)</span>
                    </div>
                    <% }} %>
                </div>
            </div>

            <div class="found-row">
                <strong>Aplicación</strong>
                <div class="word-box-container">
                    <% for (Map.Entry<String,Integer> e : appCounts.entrySet()) {
                        if (e.getValue() > 0) {
                            String appNorm = e.getKey();
                            String appLabel = displayLabel.get(appNorm);
                            List<String> words = appToWords.get(appLabel);
                            StringBuilder sbWords = new StringBuilder();
                            if (words != null) {
                                for (String w : words) {
                                    if (sbWords.length() > 0) sbWords.append("|");
                                    sbWords.append(w.trim());
                                }
                            }
                    %>
                    <div class="word-box app-box parent-word"
                         data-key="<%= escapeHtml(appLabel) %>"
                         data-words="<%= escapeHtml(sbWords.toString()) %>"
                         data-visibility="true">
                        <div class="word-circle"></div>
                        <span><%= escapeHtml(appLabel) %> (<%=e.getValue()%>)</span>
                    </div>
                    <% }} %>
                </div>
            </div>

            <div class="found-row">
                <strong>Palabras del rastro</strong>
                <div class="word-box-container">
                    <% for (Map.Entry<String,Integer> e : rastroCounts.entrySet()) {
                        if (e.getValue() > 0) {
                            String rastroWord = displayLabel.get(e.getKey());
                            String parentApp = "";
                            for (Map.Entry<String, List<String>> appEntry : appToWords.entrySet()) {
                                if (appEntry.getValue().contains(rastroWord)) {
                                    parentApp = appEntry.getKey();
                                    break;
                                }
                            }
                    %>
                    <div class="word-box rastro-word"
                         data-key="<%= escapeHtml(rastroWord) %>"
                         data-parent="<%= escapeHtml(parentApp) %>"
                         data-visibility="true">
                        <div class="word-circle"></div>
                        <span><%= escapeHtml(rastroWord) %> (<%=e.getValue()%>)</span>
                    </div>
                    <% }} %>
                </div>
            </div>

            <button id="resetFiltersBtn" type="button">Quitar filtros de palabras</button>

        </div>

        <% } %>

        <div class="filter-visual">
            <button type="button" class="vis-btn green active" id="btnVerVisibles">🟢 Ver visibles</button>
            <button type="button" class="vis-btn red" id="btnVerOcultas">🔴 Ver ocultas (<%=ocultasCount%>)</button>
            <button type="button" class="vis-btn fav" id="btnVerFavoritos">⭐ Ver favoritos</button>
        </div>

        <div class="table-wrap">
            <table>
                <thead>
                    <tr>
                        <th class="col-fecha">
                            <select id="ordenSelect" onchange="setOrden(this.value)">
                                <option value="DESC" <%= "DESC".equals(orden) ? "selected" : "" %>>Más reciente</option>
                                <option value="ASC" <%= "ASC".equals(orden) ? "selected" : "" %>>Más antiguo</option>
                            </select>
                        </th>
                        <th>Asunto</th>
                        <th>Solución</th>
                        <th class="col-visual">Visual</th>
                    </tr>
                </thead>

                <tbody id="incidenciasBody">

                    <% if (paginatedRows.isEmpty()) { %>

                    <tr>
                        <td colspan="4" style="text-align:center; padding:20px; font-weight:bold; color:#c00;">
                            No encontrado
                        </td>
                    </tr>

                    <% } else {

                    List<String> highlightTermsList = new ArrayList<>();

                    if (hasText) highlightTermsList.add(q);

                    if (hasApps && modulabSelected != null) {
                        for (String appName : modulabSelected) {
                            List<String> ws = appToWords.get(appName);
                            if (ws != null) highlightTermsList.addAll(ws);
                        }
                    }

                    for (Row r : paginatedRows) {
                        String asuntoHtml = highlightTerms(r.asunto, highlightTermsList);
                        String solucionHtml = highlightTerms(r.solucion, highlightTermsList);
                        boolean esFavorito = (r.visual == 3);
                    %>

                    <tr data-visual="<%=r.visual%>" class="<%= esFavorito ? "favorito" : "" %>">
                        <td class="col-fecha"><%= r.fecha %></td>
                        <td><%= asuntoHtml %></td>
                        <td><%= solucionHtml %></td>
                        <td class="col-visual">
                            <div class="circle <%= r.visual == 1 ? "red" : "green" %>"
                                 onclick="toggleVisual('<%= escapeHtml(r.asunto) %>',
                                                       '<%= escapeHtml(r.solucion) %>',
                                                       '<%= r.fecha %>',
                                                       this)">
                            </div>
                            <div class="star <%= esFavorito ? "fav-star" : "" %>"
                                 onclick="toggleFavorito('<%= escapeHtml(r.asunto) %>',
                                                         '<%= escapeHtml(r.solucion) %>',
                                                         '<%= r.fecha %>',
                                                         this)">
                                ⭐
                            </div>
                        </td>
                    </tr>

                    <% }} %>

                </tbody>
            </table>
        </div>

        <% if (hasSearch && rows.size() > pageSize) { %>
        <div class="pagination">
            <button onclick="goToPage(<%= Math.max(1, pageNum - 1) %>)" <%= pageNum <= 1 ? "disabled" : "" %>>
                ← Página Anterior
            </button>
            
            <span class="pagination-info">
                Página <strong><%= pageNum %></strong> de <strong><%= totalPages %></strong>
                (<strong><%= rows.size() %></strong> total)
            </span>
            
            <button onclick="goToPage(<%= Math.min(totalPages, pageNum + 1) %>)" <%= pageNum >= totalPages ? "disabled" : "" %>>
                Página Siguiente →
            </button>
        </div>
        <% } %>

    </div>
</div>

<script>
function setOrden(ord) {
    document.getElementById("ordenInput").value = ord;
    document.getElementById("pageNumInput").value = "1";
    document.getElementById("buscadorForm").submit();
}

function goToPage(pageNum) {
    document.getElementById("pageNumInput").value = pageNum;
    document.getElementById("buscadorForm").submit();
}

function toggleModulabSelect() {
    const box = document.getElementById("modulabSelect");
    box.style.display = (box.style.display === "block") ? "none" : "block";
}

function toggleModulabAll() {
    const all = document.getElementById("modulabAll");
    const items = document.querySelectorAll('input[name="modulab[]"]');
    items.forEach(cb => cb.checked = all.checked);
}

document.addEventListener("change", function (e) {
    if (e.target.name === "modulab[]") {
        const all = document.getElementById("modulabAll");
        const items = document.querySelectorAll('input[name="modulab[]"]');
        const allChecked = Array.from(items).every(cb => cb.checked);
        all.checked = allChecked;
    }
});

function norm(str) {
    if (!str) return "";
    return str
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/[^a-z0-9 ]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

document.addEventListener("DOMContentLoaded", function () {
    const wordBoxes = document.querySelectorAll(".word-box");
    const rows = document.querySelectorAll("#incidenciasBody tr");
    const resetBtn = document.getElementById("resetFiltersBtn");

    const activeFilters = new Set();
    const wordVisibility = {};

    wordBoxes.forEach(box => {
        const key = box.dataset.key;
        wordVisibility[key] = true;
    });

    function rowContainsAnyActive(row) {
        if (activeFilters.size === 0) return true;
        const asunto = norm(row.children[1].innerText);
        const solucion = norm(row.children[2].innerText);
        for (const k of activeFilters) {
            const kn = norm(k);
            if (!kn) continue;
            if (asunto.includes(kn) || solucion.includes(kn)) return true;
        }
        return false;
    }

    function updateWordBoxUI(box) {
        const key = box.dataset.key;
        const circle = box.querySelector(".word-circle");
        const isVisible = wordVisibility[key] !== false;
        
        if (isVisible) {
            if (circle) circle.classList.remove("off");
        } else {
            if (circle) circle.classList.add("off");
        }
    }

    function applyFilters() {
        rows.forEach(row => {
            const passFilter = rowContainsAnyActive(row);
            
            const asunto = norm(row.children[1].innerText);
            const solucion = norm(row.children[2].innerText);
            let allHidden = false;
            
            for (const key in wordVisibility) {
                if (wordVisibility[key] === false) {
                    const kn = norm(key);
                    if (kn && (asunto.includes(kn) || solucion.includes(kn))) {
                        allHidden = true;
                        break;
                    }
                }
            }
            
            row.style.display = (passFilter && !allHidden) ? "" : "none";
        });
    }

    wordBoxes.forEach(box => {
        const key = box.dataset.key;
        const circle = box.querySelector(".word-circle");
        const isParentWord = box.classList.contains("parent-word");

        box.addEventListener("click", function (e) {
            if (e.target === circle) return;

            if (activeFilters.has(key)) {
                activeFilters.delete(key);
                box.classList.remove("active-filter");
            } else {
                activeFilters.add(key);
                box.classList.add("active-filter");
            }
            applyFilters();
        });

        if (circle) {
            circle.addEventListener("click", function (e) {
                e.stopPropagation();

                if (isParentWord) {
                    const childWords = box.dataset.words.split("|");
                    const newVis = !(wordVisibility[key] !== false);
                    
                    wordVisibility[key] = newVis;
                    childWords.forEach(childWord => {
                        wordVisibility[childWord.trim()] = newVis;
                        wordBoxes.forEach(childBox => {
                            if (childBox.dataset.key === childWord.trim()) {
                                const c = childBox.querySelector(".word-circle");
                                if (c) {
                                    if (newVis) {
                                        c.classList.remove("off");
                                    } else {
                                        c.classList.add("off");
                                    }
                                }
                            }
                        });
                    });
                } else {
                    wordVisibility[key] = !(wordVisibility[key] !== false);
                }

                updateWordBoxUI(box);
                applyFilters();
            });
        }
    });

    if (resetBtn) {
        resetBtn.addEventListener("click", () => {
            activeFilters.clear();
            wordBoxes.forEach(b => {
                b.classList.remove("active-filter");
                wordVisibility[b.dataset.key] = true;
                const c = b.querySelector(".word-circle");
                if (c) c.classList.remove("off");
            });
            rows.forEach(r => r.style.display = "");
        });
    }

    const btnVis = document.getElementById("btnVerVisibles");
    const btnOcu = document.getElementById("btnVerOcultas");
    const btnFav = document.getElementById("btnVerFavoritos");

    function applyVisualFilter() {
        const showOcultas = btnOcu.classList.contains("active");
        const showFavoritos = btnFav.classList.contains("active");

        rows.forEach(r => {
            const v = r.getAttribute("data-visual");
            let shouldShowByVisual = true;

            if (showFavoritos) {
                shouldShowByVisual = (v === "3");
            } else if (showOcultas) {
                shouldShowByVisual = (v === "1");
            } else {
                shouldShowByVisual = (v === "0" || v === "3");
            }

            r.dataset.visualFiltered = shouldShowByVisual ? "0" : "1";
        });

        applyCombinedFilters();
    }

    function applyCombinedFilters() {
        rows.forEach(r => {
            const vf = r.dataset.visualFiltered === "1";
            const wf = !rowContainsAnyActive(r);
            
            let wordHidden = false;
            const asunto = norm(r.children[1].innerText);
            const solucion = norm(r.children[2].innerText);
            for (const key in wordVisibility) {
                if (wordVisibility[key] === false) {
                    const kn = norm(key);
                    if (kn && (asunto.includes(kn) || solucion.includes(kn))) {
                        wordHidden = true;
                        break;
                    }
                }
            }
            
            r.style.display = (!vf && !wf && !wordHidden) ? "" : "none";
        });
    }

    btnVis.addEventListener("click", function () {
        btnVis.classList.add("active");
        btnOcu.classList.remove("active");
        btnFav.classList.remove("active");
        applyVisualFilter();
    });

    btnOcu.addEventListener("click", function () {
        btnOcu.classList.add("active");
        btnVis.classList.remove("active");
        btnFav.classList.remove("active");
        applyVisualFilter();
    });

    btnFav.addEventListener("click", function () {
        btnFav.classList.add("active");
        btnVis.classList.remove("active");
        btnOcu.classList.remove("active");
        applyVisualFilter();
    });

    rows.forEach(r => {
        r.dataset.wordFiltered = "0";
        r.dataset.visualFiltered = "0";
    });

    applyVisualFilter();
});

function toggleVisual(asunto, solucion, fecha, el) {
    const isGreen = el.classList.contains("green");
    const newVal = isGreen ? 1 : 0;

    fetch("updateVisual.jsp?asunto=" + encodeURIComponent(asunto) +
          "&solucion=" + encodeURIComponent(solucion) +
          "&fecha=" + encodeURIComponent(fecha) +
          "&value=" + newVal)
        .then(r => r.text())
        .then(t => {
            if (t.trim() === "OK") {
                el.classList.toggle("green");
                el.classList.toggle("red");

                const tr = el.closest("tr");
                const star = tr.querySelector(".star");

                if (newVal === 1) {
                    tr.setAttribute("data-visual", "1");
                    tr.classList.remove("favorito");
                    if (star) star.classList.remove("fav-star");
                } else {
                    tr.setAttribute("data-visual", "0");
                }

                const rows = document.querySelectorAll("#incidenciasBody tr");
                const btnOcu = document.getElementById("btnVerOcultas");
                const btnFav = document.getElementById("btnVerFavoritos");
                const showOcultas = btnOcu.classList.contains("active");
                const showFavoritos = btnFav.classList.contains("active");

                rows.forEach(r => {
                    const v = r.getAttribute("data-visual");
                    let visible = true;
                    if (showFavoritos) visible = (v === "3");
                    else if (showOcultas) visible = (v === "1");
                    else visible = (v === "0" || v === "3");
                    r.dataset.visualFiltered = visible ? "0" : "1";
                    if (!r.dataset.wordFiltered) r.dataset.wordFiltered = "0";
                });

                const showFav = btnFav.classList.contains("active");
                rows.forEach(r => {
                    const wf = r.dataset.wordFiltered === "1";
                    const vf = r.dataset.visualFiltered === "1";
                    const v = r.getAttribute("data-visual");
                    if (showFav && v === "3" && !wf) {
                        r.style.display = "";
                    } else {
                        r.style.display = (!wf && !vf) ? "" : "none";
                    }
                });
            }
        });
}

function toggleFavorito(asunto, solucion, fecha, el) {
    const isFav = el.classList.contains("fav-star");
    const newVal = isFav ? 0 : 3;

    fetch("updateFavorito.jsp?asunto=" + encodeURIComponent(asunto) +
          "&solucion=" + encodeURIComponent(solucion) +
          "&fecha=" + encodeURIComponent(fecha) +
          "&value=" + newVal)
        .then(r => r.text())
        .then(t => {
            if (t.trim() === "OK") {
                el.classList.toggle("fav-star");

                const tr = el.closest("tr");
                const circle = tr.querySelector(".circle");

                if (newVal === 3) {
                    tr.classList.add("favorito");
                    tr.setAttribute("data-visual", "3");
                    if (circle && !circle.classList.contains("green")) {
                        circle.classList.remove("red");
                        circle.classList.add("green");
                    }
                } else {
                    tr.classList.remove("favorito");
                    tr.setAttribute("data-visual", "0");
                }

                const rows = document.querySelectorAll("#incidenciasBody tr");
                const btnOcu = document.getElementById("btnVerOcultas");
                const btnFav = document.getElementById("btnVerFavoritos");
                const showOcultas = btnOcu.classList.contains("active");
                const showFavoritos = btnFav.classList.contains("active");

                rows.forEach(r => {
                    const v = r.getAttribute("data-visual");
                    let visible = true;
                    if (showFavoritos) visible = (v === "3");
                    else if (showOcultas) visible = (v === "1");
                    else visible = (v === "0" || v === "3");
                    r.dataset.visualFiltered = visible ? "0" : "1";
                    if (!r.dataset.wordFiltered) r.dataset.wordFiltered = "0";
                });

                const showFav = btnFav.classList.contains("active");
                rows.forEach(r => {
                    const wf = r.dataset.wordFiltered === "1";
                    const vf = r.dataset.visualFiltered === "1";
                    const v = r.getAttribute("data-visual");
                    if (showFav && v === "3" && !wf) {
                        r.style.display = "";
                    } else {
                        r.style.display = (!wf && !vf) ? "" : "none";
                    }
                });
            }
        });
}
</script>

</body>
</html>
