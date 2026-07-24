<?php
$code = strtoupper(preg_replace('/[^A-Fa-f0-9]+/', '', (string)($_GET['code'] ?? '')));
$code = substr($code, 0, 8);
$appUrl = $code !== '' ? "llb://telegram-link/$code" : 'llb://';
$webUrl = 'https://llb.panfilius.ru/flutter_app/';
?>
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Привязать Telegram</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f7faf5;
      color: #15211c;
    }
    main {
      width: min(420px, calc(100vw - 40px));
      display: grid;
      gap: 18px;
      text-align: center;
    }
    h1 {
      margin: 0;
      font-size: 28px;
      line-height: 1.15;
    }
    p {
      margin: 0;
      color: #4d5a53;
      line-height: 1.4;
    }
    a {
      display: block;
      padding: 15px 18px;
      border-radius: 12px;
      background: #0d6b4f;
      color: white;
      text-decoration: none;
      font-weight: 700;
    }
    a.secondary {
      background: transparent;
      color: #0d6b4f;
      border: 1px solid #bbcac3;
    }
  </style>
</head>
<body>
  <main>
    <h1>Привязка Telegram</h1>
    <p>Откройте приложение и войдите в аккаунт, чтобы бот понял, кто вы.</p>
    <a href="<?= htmlspecialchars($appUrl, ENT_QUOTES) ?>">Открыть приложение</a>
    <a class="secondary" href="<?= htmlspecialchars($webUrl, ENT_QUOTES) ?>">Открыть web-версию</a>
  </main>
  <script>
    const appUrl = <?= json_encode($appUrl, JSON_UNESCAPED_SLASHES) ?>;
    const webUrl = <?= json_encode($webUrl, JSON_UNESCAPED_SLASHES) ?>;
    const openedAt = Date.now();
    location.href = appUrl;
    setTimeout(() => {
      if (Date.now() - openedAt < 1800) {
        location.href = webUrl;
      }
    }, 1200);
  </script>
</body>
</html>
