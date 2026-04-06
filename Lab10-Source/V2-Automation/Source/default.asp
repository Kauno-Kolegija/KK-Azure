<html lang="lt">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lankytojų Seklys v2</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            height: 100vh;
            margin: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            color: #333;
        }
        .card {
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 500px;
            width: 90%;
            border-top: 5px solid #0078d4;
        }
        h1 { margin-top: 0; color: #0078d4; }
        .info {
            background: #e1f5fe;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            text-align: left;
            font-family: monospace;
            font-size: 1.1em;
            color: #0277bd;
        }
        .footer {
            margin-top: 20px;
            font-size: 0.9em;
            color: #666;
        }
        .status-icon { font-size: 3em; margin-bottom: 10px; display: block; }
    </style>
</head>
<body>

    <div class="card">
        <span class="status-icon"><VARDAS>🕵️‍♂️</span>
        <h1>Lankytojas Užfiksuotas!</h1>
        <p>Jūsų apsilankymas sėkmingai įrašytas į saugumo žurnalą.</p>
        
        <div class="info">
            <strong>Failas:</strong> <%=fileName%><br>
            <strong>Laikas:</strong> <%=Now()%><br>
            <strong>Jūsų IP:</strong> <%=clientIP%>
        </div>
    </div>

</body>
</html>
