<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$configPath = __DIR__ . '/../llb_api_config.php';
if (!is_file($configPath)) {
    $configPath = dirname(__DIR__, 2) . '/llb_api_config.php';
}
if (!is_file($configPath)) {
    http_response_code(500);
    echo json_encode(['error' => 'config_missing'], JSON_UNESCAPED_UNICODE);
    exit;
}
$config = require $configPath;

function respond($data, int $status = 200): void {
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function int_param(string $name, int $default, int $min = 0, int $max = 1000): int {
    $value = isset($_GET[$name]) ? (int)$_GET[$name] : $default;
    return max($min, min($max, $value));
}

function json_body(): array {
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function crypto_key(array $config): string {
    $secret = (string)($config['app_secret'] ?? $config['password'] ?? 'llb-mobile');
    return hash('sha256', $secret, true);
}

function encrypt_secret(string $value, array $config): array {
    $iv = random_bytes(12);
    $tag = '';
    $ciphertext = openssl_encrypt(
        $value,
        'aes-256-gcm',
        crypto_key($config),
        OPENSSL_RAW_DATA,
        $iv,
        $tag
    );
    if ($ciphertext === false) {
        throw new RuntimeException('encrypt_failed');
    }
    return [
        'ciphertext' => base64_encode($ciphertext),
        'iv' => base64_encode($iv),
        'tag' => base64_encode($tag),
    ];
}

function fetch_text(string $url): string {
    $context = stream_context_create([
        'http' => [
            'timeout' => 12,
            'header' => "User-Agent: Mozilla/5.0 (compatible; llb-mobile/1.0)\r\n",
        ],
        'ssl' => [
            'verify_peer' => true,
            'verify_peer_name' => true,
        ],
    ]);
    $body = @file_get_contents($url, false, $context);
    return is_string($body) ? $body : '';
}

function node_text(?DOMNode $node): string {
    if (!$node) {
        return '';
    }
    return trim(preg_replace('/\s+/u', ' ', html_entity_decode($node->textContent, ENT_QUOTES | ENT_HTML5, 'UTF-8')) ?? '');
}

function player_stats_from_detail($detailJson): array {
    $detail = is_string($detailJson) && $detailJson !== '' ? json_decode($detailJson, true) : null;
    if (!is_array($detail)) {
        return [];
    }
    $sections = $detail['_sections'] ?? [];
    $statsText = is_array($sections) ? (string)($sections['Статистика'] ?? '') : '';
    if ($statsText === '') {
        return [];
    }
    $labels = [
        'total' => 'Турниров',
        'pyramid' => 'Пирамида',
        'pool' => 'Пул',
        'snooker' => 'Снукер',
    ];
    $stats = [];
    foreach ($labels as $key => $label) {
        if (preg_match('/' . preg_quote($label, '/') . '\s*:\s*(\d+)/u', $statsText, $m)) {
            $stats[$key] = (int)$m[1];
        }
    }
    return $stats;
}

function absolute_url(string $url, string $base): string {
    $url = trim($url);
    if ($url === '') {
        return '';
    }
    if (preg_match('/^https?:\/\//i', $url)) {
        return $url;
    }
    if (str_starts_with($url, '//')) {
        return 'https:' . $url;
    }
    return rtrim($base, '/') . '/' . ltrim($url, '/');
}

function parse_live_participants(int $compId): array {
    $competitionHtml = fetch_text("https://t.llb.su/competition.php?comp={$compId}");
    if ($competitionHtml === '') {
        return [];
    }
    $stageIds = [];
    if (preg_match('/<a[^>]+class=["\'][^"\']*\bact\b[^"\']*["\'][^>]+href=["\'][^"\']*stage=(\d+)/iu', $competitionHtml, $m)) {
        $stageIds[] = (int)$m[1];
    }
    if (preg_match_all('/participants\.php\?comp=' . preg_quote((string)$compId, '/') . '&stage=(\d+)/iu', $competitionHtml, $m)) {
        foreach ($m[1] as $stageId) {
            $stageIds[] = (int)$stageId;
        }
    }
    if (preg_match_all('/stage=(\d+)/iu', $competitionHtml, $m)) {
        foreach ($m[1] as $stageId) {
            $stageIds[] = (int)$stageId;
        }
    }
    $stageIds = array_values(array_unique(array_filter($stageIds)));
    if (!$stageIds) {
        return [];
    }

    $participants = [];
    foreach ($stageIds as $stageId) {
        $html = fetch_text("https://t.llb.su/participants.php?comp={$compId}&stage={$stageId}");
        if ($html === '') {
            continue;
        }

        $dom = new DOMDocument();
        libxml_use_internal_errors(true);
        $loaded = $dom->loadHTML('<?xml encoding="utf-8" ?>' . $html);
        libxml_clear_errors();
        if (!$loaded) {
            continue;
        }
        $xpath = new DOMXPath($dom);
        $rows = $xpath->query('//table[@id="participants"]//tr');
        foreach ($rows ?: [] as $row) {
            $cells = $xpath->query('./td', $row);
            if (!$cells || $cells->length < 6) {
                continue;
            }
            $link = $xpath->query('.//a', $cells->item(1))->item(0);
            if (!$link instanceof DOMElement) {
                continue;
            }
            $href = $link->getAttribute('href');
            $playerId = null;
            if (preg_match('/(?:[?&]id=|\/node\/)(\d+)/', $href, $m)) {
                $playerId = (int)$m[1];
            }
            if (!$playerId || isset($participants[$playerId])) {
                continue;
            }
            $image = $xpath->query('.//img', $cells->item(1))->item(0);
            $avatarUrl = $image instanceof DOMElement
                ? absolute_url($image->getAttribute('src'), 'https://t.llb.su')
                : '';
            $participants[$playerId] = [
                'player_id' => $playerId,
                'seed' => (int)node_text($cells->item(0)),
                'name' => node_text($link),
                'birth_year' => node_text($cells->item(2)),
                'rank' => node_text($cells->item(3)),
                'country' => node_text($cells->item(4)),
                'city' => node_text($cells->item(5)),
                'place' => $cells->length >= 7 ? node_text($cells->item(6)) : '',
                'avatar_url' => $avatarUrl,
                'elo' => null,
                'best_elo' => null,
                'rating_keys' => '',
                'rating_summary' => '',
            ];
        }
    }
    return array_values($participants);
}

function parse_registered_participants(int $tournamentId): array {
    $html = fetch_text("https://www.llb.su/t/{$tournamentId}");
    if ($html === '') {
        return [];
    }

    $dom = new DOMDocument();
    libxml_use_internal_errors(true);
    $loaded = $dom->loadHTML('<?xml encoding="utf-8" ?>' . $html);
    libxml_clear_errors();
    if (!$loaded) {
        return [];
    }
    $xpath = new DOMXPath($dom);
    $rows = $xpath->query('//div[contains(concat(" ", normalize-space(@class), " "), " view-competition-participants ")]//tbody/tr');
    $participants = [];
    foreach ($rows ?: [] as $row) {
        $cells = $xpath->query('./td', $row);
        if (!$cells || $cells->length < 2) {
            continue;
        }
        $link = $xpath->query('.//a', $cells->item(1))->item(0);
        if (!$link instanceof DOMElement) {
            continue;
        }
        $registrationNodeId = null;
        if (preg_match('/\/node\/(\d+)/', $link->getAttribute('href'), $m)) {
            $registrationNodeId = (int)$m[1];
        }
        $name = node_text($link);
        if ($name === '') {
            continue;
        }
        $participants[] = [
            'player_id' => null,
            'registration_node_id' => $registrationNodeId,
            'seed' => (int)node_text($cells->item(0)),
            'name' => $name,
            'birth_year' => '',
            'rank' => '',
            'country' => '',
            'city' => '',
            'place' => $cells->length >= 3 ? node_text($cells->item(2)) : '',
            'avatar_url' => '',
            'elo' => null,
            'best_elo' => null,
            'rating_keys' => '',
            'rating_summary' => '',
        ];
    }
    return $participants;
}

function merge_participants(array $primary, array $fallback): array {
    $byId = [];
    $byFallbackKey = [];
    foreach ($primary as $participant) {
        $playerId = (int)($participant['player_id'] ?? 0);
        if ($playerId > 0) {
            $byId[$playerId] = $participant;
        }
        $key = participant_fallback_key($participant);
        if ($key !== '') {
            $byFallbackKey[$key] = $participant;
        }
    }
    $merged = [];
    foreach ($fallback as $participant) {
        $playerId = (int)($participant['player_id'] ?? 0);
        if ($playerId > 0) {
            if (isset($byId[$playerId])) {
                $matched = $byId[$playerId];
                $merged[] = array_merge($participant, $matched);
                unset($byFallbackKey[participant_fallback_key($matched)]);
            } else {
                $merged[] = $participant;
            }
            unset($byId[$playerId]);
            continue;
        }
        $key = participant_fallback_key($participant);
        if ($key !== '' && isset($byFallbackKey[$key])) {
            $merged[] = array_merge($participant, $byFallbackKey[$key]);
            unset($byFallbackKey[$key]);
        } else {
            $merged[] = $participant;
        }
    }
    foreach ($byId as $participant) {
        $merged[] = $participant;
    }
    foreach ($byFallbackKey as $participant) {
        $merged[] = $participant;
    }
    return $merged;
}

function enrich_participants_by_player_id(PDO $pdo, array $participants): array {
    $ids = [];
    foreach ($participants as $participant) {
        $playerId = (int)($participant['player_id'] ?? 0);
        if ($playerId > 0) {
            $ids[$playerId] = true;
        }
    }
    if (!$ids) {
        return $participants;
    }

    $idList = array_keys($ids);
    $placeholders = implode(',', array_fill(0, count($idList), '?'));
    $stmt = $pdo->prepare("SELECT p.id AS player_id, p.elo,
                                  MAX(r.elo) AS best_elo,
                                  GROUP_CONCAT(DISTINCT r.rating_key ORDER BY r.rating_key SEPARATOR ',') AS rating_keys,
                                  GROUP_CONCAT(
                                    DISTINCT CONCAT_WS('::', r.rating_key, COALESCE(r.elo, ''), r.discipline, r.rating_label, r.comps_year, r.comps_total)
                                    ORDER BY r.elo DESC SEPARATOR '|'
                                  ) AS rating_summary
                           FROM players p
                           LEFT JOIN player_ratings r ON r.player_id = p.id
                           WHERE p.id IN ({$placeholders})
                           GROUP BY p.id");
    foreach ($idList as $index => $id) {
        $stmt->bindValue($index + 1, $id, PDO::PARAM_INT);
    }
    $stmt->execute();

    $byId = [];
    foreach ($stmt->fetchAll() as $row) {
        $byId[(int)$row['player_id']] = $row;
    }

    foreach ($participants as &$participant) {
        $playerId = (int)($participant['player_id'] ?? 0);
        if ($playerId <= 0 || !isset($byId[$playerId])) {
            continue;
        }
        foreach (['elo', 'best_elo', 'rating_keys', 'rating_summary'] as $field) {
            if (($participant[$field] ?? null) === null || ($participant[$field] ?? '') === '') {
                $participant[$field] = $byId[$playerId][$field] ?? $participant[$field] ?? null;
            }
        }
    }
    unset($participant);

    return $participants;
}

function fetch_archive_participants(PDO $pdo, int $tournamentId): array {
    $stmt = $pdo->prepare('SELECT ap.tournament_id, ap.membership_node_id, ap.seed, ap.name,
                                  ap.level AS `rank`, ap.points, ap.place,
                                  pte.player_id, p.avatar_url, p.elo,
                                  MAX(r.elo) AS best_elo,
                                  GROUP_CONCAT(DISTINCT r.rating_key ORDER BY r.rating_key SEPARATOR \',\') AS rating_keys,
                                  GROUP_CONCAT(
                                    DISTINCT CONCAT_WS(\'::\', r.rating_key, COALESCE(r.elo, \'\'), r.discipline, r.rating_label, r.comps_year, r.comps_total)
                                    ORDER BY r.elo DESC SEPARATOR \'|\'
                                  ) AS rating_summary
                           FROM archive_tournament_participants ap
                           LEFT JOIN player_tournament_entries pte
                             ON pte.tournament_id = ap.tournament_id
                            AND pte.membership_node_id = ap.membership_node_id
                            AND ap.membership_node_id > 0
                           LEFT JOIN players p ON p.id = pte.player_id
                           LEFT JOIN player_ratings r ON r.player_id = pte.player_id
                           WHERE ap.tournament_id = :id
                           GROUP BY ap.tournament_id, ap.membership_node_id, ap.name, pte.player_id
                           ORDER BY COALESCE(ap.seed, 999999), ap.name
                           LIMIT 500');
    $stmt->execute([':id' => $tournamentId]);
    return $stmt->fetchAll();
}

function participant_fallback_key(array $participant): string {
    $registrationNodeId = (string)($participant['registration_node_id'] ?? '');
    if ($registrationNodeId !== '') {
        return 'registration:' . $registrationNodeId;
    }
    return '';
}

function ensure_llb_app_users_table(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS llb_app_users (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        llb_username VARCHAR(190) NOT NULL,
        llb_username_hash CHAR(64) NOT NULL,
        password_ciphertext TEXT NOT NULL,
        password_iv VARCHAR(64) NOT NULL,
        password_tag VARCHAR(64) NOT NULL,
        request_ip VARCHAR(64) NULL,
        user_agent VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        last_login_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_llb_username_hash (llb_username_hash)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
}

function ensure_video_streams_table(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS video_streams (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        tournament_id BIGINT NOT NULL,
        player_id BIGINT NULL,
        provider VARCHAR(32) NOT NULL DEFAULT "youtube",
        status VARCHAR(32) NOT NULL DEFAULT "requested",
        title VARCHAR(255) NULL,
        playback_url TEXT NULL,
        obs_node VARCHAR(128) NULL,
        requested_by VARCHAR(190) NULL,
        request_ip VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        started_at TIMESTAMP NULL,
        ended_at TIMESTAMP NULL,
        KEY idx_video_streams_tournament (tournament_id),
        KEY idx_video_streams_player (player_id),
        KEY idx_video_streams_status (status),
        UNIQUE KEY uniq_video_stream_request (tournament_id, player_id, provider, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    try {
        $pdo->exec('ALTER TABLE video_streams ADD UNIQUE KEY uniq_video_stream_request (tournament_id, player_id, provider, status)');
    } catch (Throwable $ignored) {
    }
}

function is_online_tournament(array $tournament): bool {
    $sourceKind = strtolower((string)($tournament['source_kind'] ?? ''));
    $statusClass = strtolower((string)($tournament['status_class'] ?? ''));
    return $sourceKind === 'online' || in_array($statusClass, ['running', 'live', 'online'], true);
}

function player_in_tournament(PDO $pdo, int $tournamentId, int $playerId): bool {
    $stmt = $pdo->prepare('SELECT comp_id FROM tournaments WHERE id = ?');
    $stmt->execute([$tournamentId]);
    $compId = (int)($stmt->fetchColumn() ?: 0);
    if ($compId > 0) {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM tournament_participants WHERE comp_id = ? AND player_id = ?');
        $stmt->execute([$compId, $playerId]);
        if ((int)$stmt->fetchColumn() > 0) {
            return true;
        }
    }

    $stmt = $pdo->prepare('SELECT COUNT(*) FROM archive_tournament_participants WHERE tournament_id = ? AND membership_node_id = ?');
    $stmt->execute([$tournamentId, $playerId]);
    return (int)$stmt->fetchColumn() > 0;
}

try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $config['host'], $config['port'], $config['database']),
        $config['user'],
        $config['password'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (Throwable $e) {
    respond(['error' => 'db_unavailable'], 500);
}

$resource = $_GET['resource'] ?? 'health';
$limit = int_param('limit', 50, 1, 200);
$offset = int_param('offset', 0, 0, 1000000);

try {
    if ($resource === 'llb_auth') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        $body = json_body();
        $username = trim((string)($body['username'] ?? ''));
        $password = (string)($body['password'] ?? '');
        if ($username === '' || $password === '') {
            respond(['error' => 'credentials_required'], 400);
        }
        if (mb_strlen($username) > 190 || strlen($password) > 1024) {
            respond(['error' => 'credentials_too_long'], 400);
        }

        ensure_llb_app_users_table($pdo);
        $encrypted = encrypt_secret($password, $config);
        $usernameHash = hash('sha256', mb_strtolower($username));
        $stmt = $pdo->prepare('INSERT INTO llb_app_users
              (llb_username, llb_username_hash, password_ciphertext, password_iv, password_tag, request_ip, user_agent, last_login_at)
              VALUES (:username, :username_hash, :ciphertext, :iv, :tag, :request_ip, :user_agent, NOW())
              ON DUPLICATE KEY UPDATE
                llb_username = VALUES(llb_username),
                password_ciphertext = VALUES(password_ciphertext),
                password_iv = VALUES(password_iv),
                password_tag = VALUES(password_tag),
                request_ip = VALUES(request_ip),
                user_agent = VALUES(user_agent),
                last_login_at = NOW()');
        $stmt->execute([
            ':username' => $username,
            ':username_hash' => $usernameHash,
            ':ciphertext' => $encrypted['ciphertext'],
            ':iv' => $encrypted['iv'],
            ':tag' => $encrypted['tag'],
            ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
            ':user_agent' => substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255),
        ]);
        respond(['ok' => true]);
    }

    if ($resource === 'health') {
        $counts = [];
        foreach (['players', 'player_ratings', 'tournaments', 'matches'] as $table) {
            $counts[$table] = (int)$pdo->query("SELECT COUNT(*) FROM `$table`")->fetchColumn();
        }
        try {
            ensure_video_streams_table($pdo);
            $counts['video_streams'] = (int)$pdo->query('SELECT COUNT(*) FROM video_streams')->fetchColumn();
        } catch (Throwable $ignored) {
            $counts['video_streams'] = 0;
        }
        respond(['ok' => true, 'counts' => $counts]);
    }

    if ($resource === 'video_streams') {
        ensure_video_streams_table($pdo);
        $sql = 'SELECT vs.id, vs.tournament_id, vs.player_id, vs.provider, vs.status, vs.title,
                       vs.playback_url, vs.obs_node, vs.requested_by, vs.created_at,
                       t.title AS tournament_title, t.date_text, t.club, t.source_kind, t.status_class,
                       p.name AS player_name
                FROM video_streams vs
                LEFT JOIN tournaments t ON t.id = vs.tournament_id
                LEFT JOIN players p ON p.id = vs.player_id
                ORDER BY
                  CASE vs.status
                    WHEN "live" THEN 0
                    WHEN "starting" THEN 1
                    WHEN "requested" THEN 2
                    ELSE 3
                  END,
                  vs.id DESC
                LIMIT :limit OFFSET :offset';
        $stmt = $pdo->prepare($sql);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        respond(['items' => $stmt->fetchAll(), 'limit' => $limit, 'offset' => $offset]);
    }

    if ($resource === 'video_stream_request') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_video_streams_table($pdo);
        $body = json_body();
        $tournamentId = (int)($body['tournament_id'] ?? 0);
        $playerId = (int)($body['player_id'] ?? 0);
        $provider = strtolower(trim((string)($body['provider'] ?? 'youtube')));
        $requestedBy = trim((string)($body['requested_by'] ?? ''));
        if ($tournamentId <= 0 || $playerId <= 0) {
            respond(['error' => 'tournament_and_player_required'], 400);
        }
        if (!in_array($provider, ['youtube', 'vk', 'rutube'], true)) {
            respond(['error' => 'bad_provider'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM tournaments WHERE id = ?');
        $stmt->execute([$tournamentId]);
        $tournament = $stmt->fetch();
        if (!$tournament) {
            respond(['error' => 'tournament_not_found'], 404);
        }
        if (!is_online_tournament($tournament)) {
            respond(['error' => 'tournament_not_online'], 409);
        }
        if (!player_in_tournament($pdo, $tournamentId, $playerId)) {
            respond(['error' => 'player_not_registered'], 403);
        }

        $stmt = $pdo->prepare('INSERT INTO video_streams
              (tournament_id, player_id, provider, status, title, requested_by, request_ip)
              VALUES (:tournament_id, :player_id, :provider, "requested", :title, :requested_by, :request_ip)
              ON DUPLICATE KEY UPDATE
                title = VALUES(title),
                requested_by = VALUES(requested_by),
                request_ip = VALUES(request_ip),
                updated_at = NOW()');
        $stmt->execute([
            ':tournament_id' => $tournamentId,
            ':player_id' => $playerId,
            ':provider' => $provider,
            ':title' => (string)($tournament['title'] ?? ''),
            ':requested_by' => $requestedBy !== '' ? $requestedBy : null,
            ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
        ]);
        respond(['ok' => true, 'id' => (int)$pdo->lastInsertId(), 'status' => 'requested']);
    }

    if ($resource === 'players') {
        $where = [];
        $params = [];
        $playerQuery = trim((string)($_GET['q'] ?? $_GET['query'] ?? ''));
        if ($playerQuery !== '') {
            $where[] = '(p.name LIKE :q OR p.city LIKE :q OR p.country LIKE :q OR p.id = :q_id)';
            $params[':q'] = '%' . $playerQuery . '%';
            $params[':q_id'] = ctype_digit($playerQuery) ? (int)$playerQuery : 0;
        }
        if (!empty($_GET['rating_key'])) {
            $where[] = 'r.rating_key = :rating_key';
            $params[':rating_key'] = $_GET['rating_key'];
        }
        $sql = 'SELECT p.id, p.name, p.city, p.country, p.avatar_url, p.elo, p.detail_fetched_at,
                       p.contacts_raw, p.phone, p.email, p.telegram, p.whatsapp,
                       MAX(r.elo) AS best_elo,
                       GROUP_CONCAT(DISTINCT r.rating_key ORDER BY r.rating_key SEPARATOR \',\') AS rating_keys,
                       GROUP_CONCAT(
                         DISTINCT CONCAT_WS(\'::\', r.rating_key, COALESCE(r.elo, \'\'), r.discipline, r.rating_label, r.comps_year, r.comps_total)
                         ORDER BY r.elo DESC SEPARATOR \'|\'
                       ) AS rating_summary
                FROM players p
                LEFT JOIN player_ratings r ON r.player_id = p.id';
        if ($where) {
            $sql .= ' WHERE ' . implode(' AND ', $where);
        }
        $sql .= ' GROUP BY p.id ORDER BY COALESCE(MAX(r.elo), p.elo, 0) DESC, p.name LIMIT :limit OFFSET :offset';
        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, $key === ':q_id' ? PDO::PARAM_INT : PDO::PARAM_STR);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        respond(['items' => $stmt->fetchAll(), 'limit' => $limit, 'offset' => $offset]);
    }

    if ($resource === 'player') {
        $id = (int)($_GET['id'] ?? 0);
        if ($id <= 0) {
            respond(['error' => 'id_required'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM players WHERE id = ?');
        $stmt->execute([$id]);
        $player = $stmt->fetch();
        if (!$player) {
            respond(['error' => 'not_found'], 404);
        }
        $stmt = $pdo->prepare('SELECT * FROM player_ratings WHERE player_id = ? ORDER BY rating_key');
        $stmt->execute([$id]);
        $player['ratings'] = $stmt->fetchAll();
        $stats = player_stats_from_detail($player['detail_json'] ?? null);
        $player['stats'] = $stats ?: new stdClass();
        $stmt = $pdo->prepare('SELECT player_id, membership_node_id, tournament_id, title, date_text, points, place, source_page, fetched_at
                               FROM player_tournament_entries
                               WHERE player_id = ?
                               ORDER BY tournament_id DESC
                               LIMIT 1000');
        $stmt->execute([$id]);
        $player['tournament_entries'] = $stmt->fetchAll();
        respond($player);
    }

    if ($resource === 'tournament') {
        $id = (int)($_GET['id'] ?? 0);
        if ($id <= 0) {
            respond(['error' => 'id_required'], 400);
        }
        $stmt = $pdo->prepare('SELECT t.id, t.title, t.source_kind, t.status_class, t.date_text, t.club,
                                      t.participants_count, t.participants_limit, t.comp_id, t.detail_fetched_at,
                                      COUNT(m.game_no) AS matches_count
                               FROM tournaments t
                               LEFT JOIN matches m ON m.tournament_id = t.id
                               WHERE t.id = :id
                               GROUP BY t.id');
        $stmt->execute([':id' => $id]);
        $tournament = $stmt->fetch();
        if (!$tournament) {
            respond(['error' => 'not_found'], 404);
        }

        $participants = [];
        $isFutureTournament = ($tournament['source_kind'] ?? '') === 'next' || ($tournament['status_class'] ?? '') === 'future';
        $registeredParticipants = [];
        if ($isFutureTournament) {
            $registeredParticipants = parse_registered_participants((int)$tournament['id']);
        }

        if ($isFutureTournament && count($registeredParticipants) > 0) {
            $participants = $registeredParticipants;
            $tournament['participants_count'] = count($registeredParticipants);
        } elseif (!empty($tournament['comp_id'])) {
            $stmt = $pdo->prepare('SELECT tp.player_id, tp.seed, tp.name, tp.birth_year, tp.rank, tp.country,
                                          tp.city, tp.place, tp.avatar_url, p.elo,
                                          MAX(r.elo) AS best_elo,
                                          GROUP_CONCAT(DISTINCT r.rating_key ORDER BY r.rating_key SEPARATOR \',\') AS rating_keys,
                                          GROUP_CONCAT(
                                            DISTINCT CONCAT_WS(\'::\', r.rating_key, COALESCE(r.elo, \'\'), r.discipline, r.rating_label, r.comps_year, r.comps_total)
                                            ORDER BY r.elo DESC SEPARATOR \'|\'
                                          ) AS rating_summary
                                   FROM tournament_participants tp
                                   LEFT JOIN players p ON p.id = tp.player_id
                                   LEFT JOIN player_ratings r ON r.player_id = tp.player_id
                                   WHERE tp.comp_id = :comp_id
                                   GROUP BY tp.comp_id, tp.stage_id, tp.player_id, tp.name
                                   ORDER BY COALESCE(tp.seed, 999999), tp.name
                                   LIMIT 300');
            $stmt->execute([':comp_id' => (int)$tournament['comp_id']]);
            $participants = $stmt->fetchAll();
            if (count($participants) < (int)$tournament['participants_count']) {
                $liveParticipants = parse_live_participants((int)$tournament['comp_id']);
                if (count($liveParticipants) > count($participants)) {
                    $participants = merge_participants($participants, $liveParticipants);
                }
            }
        }
        if (!$isFutureTournament && count($participants) < (int)$tournament['participants_count']) {
            $registeredParticipants = parse_registered_participants((int)$tournament['id']);
            if (count($registeredParticipants) > count($participants)) {
                $participants = merge_participants($participants, $registeredParticipants);
            }
        }
        $expectedParticipants = (int)($tournament['participants_count'] ?? 0);
        if (!$isFutureTournament && ($expectedParticipants === 0 || count($participants) < $expectedParticipants)) {
            $archiveParticipants = fetch_archive_participants($pdo, (int)$tournament['id']);
            if (count($archiveParticipants) > count($participants)) {
                $participants = merge_participants($participants, $archiveParticipants);
            }
        }
        $participants = enrich_participants_by_player_id($pdo, $participants);
        if (count($participants) > (int)$tournament['participants_count']) {
            $tournament['participants_count'] = count($participants);
        }

        $tournament['bracket_url'] = !empty($tournament['comp_id'])
            ? 'https://t.llb.su/competition.php?comp=' . (int)$tournament['comp_id']
            : 'https://www.llb.su/t/' . (int)$tournament['id'];

        $stmt = $pdo->prepare('SELECT comp_id, stage_id, game_no, round_name, status_class,
                                      player1_id, player1_name, player1_elo_before, player1_elo_after,
                                      player2_id, player2_name, player2_elo_before, player2_elo_after,
                                      score1, score2, table_no, planned_at, started_at, finished_at, video
                               FROM matches
                               WHERE tournament_id = :id
                               ORDER BY comp_id, stage_id, game_no
                               LIMIT 500');
        $stmt->execute([':id' => $id]);
        $tournament['participants'] = $participants;
        $tournament['matches'] = $isFutureTournament ? [] : $stmt->fetchAll();
        if ($isFutureTournament) {
            $tournament['matches_count'] = 0;
        }
        respond($tournament);
    }

    if ($resource === 'tournaments') {
        $where = [];
        $params = [];
        $status = strtolower(trim((string)($_GET['status'] ?? $_GET['status_class'] ?? '')));
        if (in_array($status, ['finished', 'past', 'results', 'result'], true)) {
            $where[] = 't.source_kind = :source_kind';
            $params[':source_kind'] = 'results';
        } elseif (in_array($status, ['upcoming', 'next', 'future'], true)) {
            $where[] = '(t.source_kind = :source_kind OR t.status_class = :status_class)';
            $where[] = 'COALESCE(
                STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%y"),
                STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%Y")
            ) >= CURDATE()';
            $params[':source_kind'] = 'next';
            $params[':status_class'] = 'future';
        } elseif (in_array($status, ['online', 'live', 'current', 'running'], true)) {
            $where[] = '(t.source_kind = :source_kind OR t.status_class IN ("running", "live"))';
            $params[':source_kind'] = 'online';
        }

        $sql = 'SELECT t.id, t.title, t.source_kind, t.status_class, t.date_text, t.club,
                                      t.participants_count, t.participants_limit, t.comp_id, t.detail_fetched_at,
                                      CASE
                                        WHEN t.source_kind = "next" OR t.status_class = "future" THEN 0
                                        ELSE COUNT(m.game_no)
                                      END AS matches_count,
                                      CASE
                                        WHEN t.comp_id IS NULL OR t.comp_id = 0 THEN CONCAT("https://www.llb.su/t/", t.id)
                                        ELSE CONCAT("https://t.llb.su/competition.php?comp=", t.comp_id)
                                      END AS bracket_url
                               FROM tournaments t
                               LEFT JOIN matches m ON m.tournament_id = t.id';
        if ($where) {
            $sql .= ' WHERE ' . implode(' AND ', $where);
        }
        $sql .= ' GROUP BY t.id
                               ORDER BY CASE
                                          WHEN t.source_kind = "next" OR t.status_class = "future" THEN
                                            COALESCE(
                                              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%y"),
                                              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%Y")
                                            )
                                          ELSE NULL
                                        END ASC,
                                        CASE
                                          WHEN t.source_kind = "next" OR t.status_class = "future" THEN 0
                                          ELSE t.id
                                        END DESC
                               LIMIT :limit OFFSET :offset';
        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, PDO::PARAM_STR);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        respond(['items' => $stmt->fetchAll(), 'limit' => $limit, 'offset' => $offset]);
    }

    if ($resource === 'matches') {
        $where = [];
        $params = [];
        if (!empty($_GET['player_id'])) {
            $where[] = '(player1_id = :player_id OR player2_id = :player_id)';
            $params[':player_id'] = (int)$_GET['player_id'];
        }
        if (!empty($_GET['tournament_id'])) {
            $where[] = 'tournament_id = :tournament_id';
            $params[':tournament_id'] = (int)$_GET['tournament_id'];
        }
        $sql = 'SELECT * FROM matches';
        if ($where) {
            $sql .= ' WHERE ' . implode(' AND ', $where);
        }
        $sql .= ' ORDER BY comp_id DESC, stage_id DESC, game_no DESC LIMIT :limit OFFSET :offset';
        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, PDO::PARAM_INT);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        respond(['items' => $stmt->fetchAll(), 'limit' => $limit, 'offset' => $offset]);
    }

    respond(['error' => 'unknown_resource'], 404);
} catch (Throwable $e) {
    respond(['error' => 'server_error'], 500);
}
