<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
<head>
    <title>Buscador Completo</title>
    <style>
        body { font-family: Arial, sans-serif; }
        .result { padding: 10px; border: 1px solid #ddd; margin: 5px 0; }
        .highlight { background-color: yellow; }
        .pagination { margin: 10px 0; }
        .page-link { margin: 0 5px; cursor: pointer; }
    </style>
    <script>
        let currentPage = 1;
        const resultsPerPage = 10;
        let results = []; // This would be populated with your actual data after initialization.

        function filterResults() {
            let input = document.getElementById("searchInput").value.toLowerCase();
            let filtered = results.filter(item => item.toLowerCase().includes(input));
            displayResults(filtered);
        }

        function displayResults(filtered) {
            let output = "";
            const start = (currentPage - 1) * resultsPerPage;
            const end = start + resultsPerPage;
            const paginatedResults = filtered.slice(start, end);

            paginatedResults.forEach((item) => {
                output += `<div class=\"result\">${highlight(item, document.getElementById(\"searchInput\").value)}</div>`;
            });

            document.getElementById("results").innerHTML = output;
            updatePagination(filtered.length);
        }

        function highlight(text, search) {
            if (!search) return text;
            const regEx = new RegExp('(\' + search + ')', 'ig');
            return text.replace(regEx, '<span class=\"highlight\">$1</span>');
        }

        function updatePagination(totalResults) {
            let pages = Math.ceil(totalResults / resultsPerPage);
            let pagination = "";
            for (let i = 1; i <= pages; i++) {
                pagination += `<span class=\"page-link\" onclick=\"changePage(${i})\">${i}</span>`;
            }
            document.getElementById("pagination").innerHTML = pagination;
        }

        function changePage(page) {
            currentPage = page;
            filterResults();
        }

        window.onload = function() {
            // Assuming results are pre-fetched
            results = ["Item 1", "Item 2", "Item 3", "Another Item", "More Data", "Searchable Item"]; // Example data
            displayResults(results);
        }
    </script>
</head>
<body>
    <h1>Buscador Completo</h1>
    <input type="text" id="searchInput" oninput="filterResults()" placeholder="Search...">
    <div id="results"></div>
    <div id="pagination" class="pagination"></div>
</body>
</html>