<%@page import="java.sql.*"%>
<%@page import="java.text.Normalizer"%>
<%@page import="java.util.*"%>
<%@page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
%>

<%!
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
        if (!t.contains(w)) return false;
    }
    return true;
}

private String highlightTerms(String text, List<String> terms) {
    if (text == null) return "";
    if (terms == null || terms.isEmpty()) return escapeHtml(text);

    String original = text;
    String lower = text.toLowerCase(Locale.ROOT);

    class R { int s,e; R(int s,int e){this.s=s;this.e=e;} }
    List<R> ranges = new ArrayList<>();

    for (String term : terms) {
        if (term == null) continue;
        term = term.trim();
        if (term.isEmpty()) continue;

        String tLower = term.toLowerCase(Locale.ROOT);
        int from = 0;
        while (true) {
            int idx = lower.indexOf(tLower, from);
            if (idx == -1) break;
            ranges.add(new R(idx, idx + tLower.length()));
            from = idx + tLower.length();
        }
    }

    if (ranges.isEmpty()) return escapeHtml(text);

    ranges.sort(Comparator.comparingInt(r -> r.s));
    List<R> merged = new ArrayList<>();
    R cur = ranges.get(0);
    for (int i = 1; i < ranges.size(); i++) {
        R r = ranges.get(i);
        if (r.s <= cur.e) {
            cur.e = Math.max(cur.e, r.e);
        } else {
            merged.add(cur);
            cur = r;
        }
    }
    merged.add(cur);

    StringBuilder out = new StringBuilder();
    int pos = 0;
    for (R r : merged) {
        if (r.s > pos) out.append(escapeHtml(original.substring(pos, r.s)));
        out.append("<span class='highlight'>");
        out.append(escapeHtml(original.substring(r.s, r.e)));
        out.append("</span>");
        pos = r.e;
    }
    if (pos < original.length()) out.append(escapeHtml(original.substring(pos)));

    return out.toString();
}
%>

<%
String q = request.getParameter("q");
String orden = request.getParameter("orden");
if (orden == null || !(orden.equals("ASC") || orden.equals("DESC"))) orden = "DESC";

String[] modulabSelected = request.getParameterValues("modulab[]");

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
        String appName = rsA.getString("aplicacion");
        String rastro  = rsA.getString("rastro");

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

class Row {
    String fecha;
    String asunto;
    String solucion;
    int visual;
    Set<String> keys = new LinkedHashSet<>();
}

List<Row> rows = new ArrayList<>();

Map<String,Integer> searchCounts = new LinkedHashMap<>();
Map<String,Integer> appCounts    = new LinkedHashMap<>();
Map<String,Integer> rastroCounts = new LinkedHashMap<>();
Map<String,String>  displayLabel = new LinkedHashMap<>();

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

        boolean whereAdded = false;

        if (hasText) {
            sql.append("WHERE (LOWER(asunto) LIKE ? OR LOWER(solucion) LIKE ?) ");
            String p = "%" + q.toLowerCase() + "%";
            params.add(p);
            params.add(p);
            whereAdded = true;
        }

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
                if (!whereAdded) sql.append("WHERE ");
                else sql.append("OR ");

                sql.append("(");
                boolean first = true;
                for (String w : allWords) {
                    if (!first) sql.append(" OR ");
                    sql.append("LOWER(asunto) LIKE ? OR LOWER(solucion) LIKE ?");
                    String p = "%" + w + "%";
                    params.add(p);
                    params.add(p);
                    first = false;
                }
                sql.append(") ");
            }
        }

        sql.append("ORDER BY fecha ").append(orden);

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
        r.fecha    = rs.getString("fecha_formateada");
        r.asunto   = rs.getString("asunto");
        r.solucion = rs.getString("solucion");
        r.visual   = rs.getInt("visual");

        boolean matchText = false;
        boolean matchApp  = false;

        if (hasText) {
            if (q.contains(" ")) {
                matchText = matchesPhrase(r.asunto, q) || matchesPhrase(r.solucion, q);
            } else {
                matchText = matchesWholeWord(r.asunto, q) || matchesWholeWord(r.solucion, q);
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
                        if (rastroCounts.containsKey(wn)) {
                            if (!r.keys.contains(wn)) {
                                rastroCounts.put(wn, rastroCounts.get(wn) + 1);
                                r.keys.add(wn);
                            }
                        }
                    }
                }

                if (rowMatchesApp) {
                    matchApp = true;

                    String appNorm = normalize(appName);
                    if (appCounts.containsKey(appNorm)) {
                        if (!r.keys.contains(appNorm)) {
                            appCounts.put(appNorm, appCounts.get(appNorm) + 1);
                            r.keys.add(appNorm);
                        }
                    }
                }
            }
        }

        if (!matchText && !matchApp && hasSearch) continue;

        if (matchText && hasText) {
            String keyNorm = normalize(q);
            if (!r.keys.contains(keyNorm)) {
                searchCounts.put(keyNorm, searchCounts.get(keyNorm) + 1);
                r.keys.add(keyNorm);
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

int ocultasCount = 0;
for (Row r : rows) if (r.visual == 1) ocultasCount++;
%>

<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Buscar incidencia</title>
<meta name="viewport" content="width=device-width, initial-scale=1">

<style>
body {
    margin: 0;
    font-family: "Segoe UI", Arial, sans-serif;
    background: #f1f4f8;
    color: #0b2540;
    padding: 20px;
}
.container { max-width: 1300px; margin: 0 auto; }

.header {
    display: flex;
    align-items: center;
    gap: 20px;
    justify-content: center;
    margin-bottom: 10px;
}
.header img { height: 80px; border-radius: 6px; }
.header h1 { margin: 0; font-size: 28px; color: #0057A8; font-weight: 700; }

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

.btn-buscar {
    padding: 10px 18px;
    border: none;
    border-radius: 6px;
    background: #0057A8;
    color: white;
    font-weight: bold;
    cursor: pointer;
}
.btn-buscar:hover { background: #004a90; }

.btn-modulab {
    background: #FFD84D;
    color: #000;
    padding: 10px 16px;
    border-radius: 6px;
    border: none;
    font-weight: bold;
    cursor: pointer;
}

.modulab-dropdown { position: relative; }
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

.small-note {
    margin-top: 8px;
    color: #555;
    font-size: 13px;
}

.found-words { margin-top: 20px; }
.found-row { margin-bottom: 12px; }
.found-row strong { display: block; margin-bottom: 6px; font-size: 15px; }

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
}

.word-box.active-filter {
    border-color: #0057A8;
    background: #e3f2fd;
}

.word-circle {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #4CAF50;
}

#resetFiltersBtn {
    margin-top: 6px;
    padding: 6px 12px;
    border-radius: 6px;
    border: 1px solid #b8c4d1;
    background: #ffffff;
    cursor: pointer;
    font-size: 13px;
}
#resetFiltersBtn:hover {
    background: #e3f2fd;
}

.filter-visual {
    margin-top: 15px;
    display: flex;
    gap: 10px;
}
.vis-btn {
    padding: 8px 12px;
    border-radius: 6px;
    border: none;
    font-weight: bold;
    cursor: pointer;
    font-size: 13px;
}
.vis-btn.green { background: #c8e6c9; }
.vis-btn.red { background: #ffcdd2; }
.vis-btn.active { outline: 2px solid #000; }

.table-wrap { margin-top: 15px; overflow-x: auto; }
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
td {
    padding: 8px 10px;
    border-bottom: 1px solid #e5e9ef;
    vertical-align: top;
    word-wrap: break-word;
    overflow-wrap: break-word;
}
th.col-fecha, td.col-fecha { width: 110px; }
th.col-visual, td.col-visual { width: 70px; }

.highlight { background: yellow; }
.col-fecha { text-align: center; white-space: nowrap; }
.col-visual { text-align: center; }

.circle {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    cursor: pointer;
    margin: auto;
}
.circle.green { background: #4CAF50; }
.circle.red { background: #e53935; }
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
                        <div class="word-box" data-key="<%=e.getKey()%>">
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
                        if (e.getValue() > 0) { %>
                        <div class="word-box" data-key="<%=e.getKey()%>">
                            <div class="word-circle"></div>
                            <span><%= escapeHtml(displayLabel.get(e.getKey())) %> (<%=e.getValue()%>)</span>
                        </div>
                    <% }} %>
                </div>
            </div>

            <div class="found-row">
                <strong>Palabras del rastro</strong>
                <div class="word-box-container">
                    <% for (Map.Entry<String,Integer> e : rastroCounts.entrySet()) {
                        if (e.getValue() > 0) { %>
                        <div class="word-box" data-key="<%=e.getKey()%>">
                            <div class="word-circle"></div>
                            <span><%= escapeHtml(displayLabel.get(e.getKey())) %> (<%=e.getValue()%>)</span>
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
        </div>

        <div class="table-wrap">
            <table>
                <thead>
                <tr>
                    <th class="col-fecha">
                        <select id="ordenSelect" onchange="setOrden(this.value)">
                            <option value="DESC" <%= "DESC".equals(orden) ? "selected" : "" %>>Más reciente</option>
                            <option value="ASC"  <%= "ASC".equals(orden)  ? "selected" : "" %>>Más antiguo</option>
                        </select>
                    </th>
                    <th>Asunto</th>
                    <th>Solución</th>
                    <th class="col-visual">Visual</th>
                </tr>
                </thead>

                <tbody id="incidenciasBody">
                <% if (rows.isEmpty()) { %>
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

                    for (Row r : rows) {
                        String asuntoHtml   = highlightTerms(r.asunto, highlightTermsList);
                        String solucionHtml = highlightTerms(r.solucion, highlightTermsList);
                %>
                    <tr data-visual="<%=r.visual%>">
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
                        </td>
                    </tr>
                <% }} %>
                </tbody>
            </table>
        </div>

    </div>
</div>

<script>
function setOrden(ord) {
    document.getElementById("ordenInput").value = ord;
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

document.addEventListener("DOMContentLoaded", function () {

    const wordBoxes = document.querySelectorAll(".word-box");
    const resetBtn = document.getElementById("resetFiltersBtn");
    const rows = document.querySelectorAll("#incidenciasBody tr");

    let activeKey = null;
    let hiddenKey = null;

    function rowContainsKey(row, key) {
        if (!key) return false;
        const asunto = row.children[1].innerText.toLowerCase();
        const solucion = row.children[2].innerText.toLowerCase();
        const k = key.toLowerCase();
        return asunto.includes(k) || solucion.includes(k);
    }

    function applyWordFilter() {
        rows.forEach(row => {
            let visible = true;

            if (activeKey) {
                visible = rowContainsKey(row, activeKey);
            }

            if (hiddenKey && rowContainsKey(row, hiddenKey)) {
                visible = false;
            }

            row.style.display = visible ? "" : "none";
        });
    }

    wordBoxes.forEach(box => {
        const circle = box.querySelector(".word-circle");
        const key = box.dataset.key;

        box.addEventListener("click", function (e) {
            if (e.target === circle) return;

            if (activeKey === key) {
                activeKey = null;
                box.classList.remove("active-filter");
            } else {
                activeKey = key;
                wordBoxes.forEach(b => b.classList.remove("active-filter"));
                box.classList.add("active-filter");
            }

            applyWordFilter();
        });

        circle.addEventListener("click", function (e) {
            e.stopPropagation();

            if (hiddenKey === key) {
                hiddenKey = null;
                circle.style.background = "#4CAF50";
            } else {
                hiddenKey = key;
                document.querySelectorAll(".word-circle").forEach(c => c.style.background = "#4CAF50");
                circle.style.background = "#e53935";
            }

            applyWordFilter();
        });
    });

    if (resetBtn) {
        resetBtn.addEventListener("click", () => {
            activeKey = null;
            hiddenKey = null;

            wordBoxes.forEach(b => {
                b.classList.remove("active-filter");
                b.querySelector(".word-circle").style.background = "#4CAF50";
            });

            rows.forEach(r => r.style.display = "");
        });
    }
});

document.addEventListener("DOMContentLoaded", function () {

    const btnVis = document.getElementById("btnVerVisibles");
    const btnOcu = document.getElementById("btnVerOcultas");
    const rows = document.querySelectorAll("#incidenciasBody tr");

    function applyVisualFilter() {
        const showOcultas = btnOcu.classList.contains("active");

        rows.forEach(r => {
            const v = r.getAttribute("data-visual");

            if (showOcultas) {
                r.style.display = (v === "1") ? "" : "none";
            } else {
                r.style.display = (v === "0") ? "" : "none";
            }
        });
    }

    btnVis.addEventListener("click", function () {
        btnVis.classList.add("active");
        btnOcu.classList.remove("active");
        applyVisualFilter();
    });

    btnOcu.addEventListener("click", function () {
        btnOcu.classList.add("active");
        btnVis.classList.remove("active");
        applyVisualFilter();
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
                tr.setAttribute("data-visual", newVal);

                const btnOcu = document.getElementById("btnVerOcultas");
                const mostrandoOcultas = btnOcu.classList.contains("active");

                if (!mostrandoOcultas && newVal === 1)
                    tr.style.display = "none";
                else if (mostrandoOcultas && newVal === 0)
                    tr.style.display = "none";
                else
                    tr.style.display = "";
            }
        });
}
</script>

</body>
</html>
