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

function ensure_column(PDO $pdo, string $table, string $column, string $definition): void {
    if (!preg_match('/^[A-Za-z0-9_]+$/', $table) || !preg_match('/^[A-Za-z0-9_]+$/', $column)) {
        throw new InvalidArgumentException('bad_identifier');
    }
    $stmt = $pdo->prepare('SELECT COUNT(*)
                           FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = :table
                             AND COLUMN_NAME = :column');
    $stmt->execute([':table' => $table, ':column' => $column]);
    if ((int)$stmt->fetchColumn() === 0) {
        $pdo->exec("ALTER TABLE `{$table}` ADD COLUMN `{$column}` {$definition}");
    }
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

function ensure_app_users_table(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS app_users (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(190) NOT NULL,
        username_hash CHAR(64) NOT NULL,
        display_name VARCHAR(255) NOT NULL,
        city VARCHAR(255) NULL,
        password_hash VARCHAR(255) NOT NULL,
        auth_token_hash CHAR(64) NULL,
        request_ip VARCHAR(64) NULL,
        user_agent VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        last_login_at TIMESTAMP NULL,
        UNIQUE KEY uniq_app_username_hash (username_hash),
        UNIQUE KEY uniq_app_auth_token_hash (auth_token_hash)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    foreach ([
        'telegram_id BIGINT NULL',
        'telegram_username VARCHAR(190) NULL',
        'telegram_chat_id BIGINT NULL',
        'telegram_linked_at TIMESTAMP NULL',
    ] as $column) {
        try {
            $pdo->exec('ALTER TABLE app_users ADD COLUMN ' . $column);
        } catch (Throwable $ignored) {
        }
    }
    try {
        $pdo->exec('ALTER TABLE app_users ADD UNIQUE KEY uniq_app_telegram_id (telegram_id)');
    } catch (Throwable $ignored) {
    }
}

function app_user_response(array $row, ?string $token = null): array {
    $user = [
        'id' => (string)($row['id'] ?? ''),
        'username' => (string)($row['username'] ?? ''),
        'display_name' => (string)($row['display_name'] ?? $row['username'] ?? ''),
        'city' => (string)($row['city'] ?? ''),
        'telegram_id' => isset($row['telegram_id']) ? (string)$row['telegram_id'] : '',
        'telegram_username' => (string)($row['telegram_username'] ?? ''),
    ];
    if ($token !== null) {
        $user['token'] = $token;
    }
    return $user;
}

function ensure_telegram_links_table(PDO $pdo): void {
    ensure_app_users_table($pdo);
    $pdo->exec('CREATE TABLE IF NOT EXISTS telegram_links (
        code_hash CHAR(64) NOT NULL PRIMARY KEY,
        telegram_id BIGINT NOT NULL,
        telegram_username VARCHAR(190) NULL,
        telegram_first_name VARCHAR(190) NULL,
        telegram_last_name VARCHAR(190) NULL,
        chat_id BIGINT NOT NULL,
        app_user_id BIGINT UNSIGNED NULL,
        claimed_at TIMESTAMP NULL,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY idx_telegram_links_telegram_id (telegram_id),
        KEY idx_telegram_links_expires (expires_at),
        KEY idx_telegram_links_app_user (app_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
}

function app_user_by_token(PDO $pdo, string $token): ?array {
    if ($token === '') {
        return null;
    }
    ensure_app_users_table($pdo);
    $stmt = $pdo->prepare('SELECT * FROM app_users WHERE auth_token_hash = ? LIMIT 1');
    $stmt->execute([hash('sha256', $token)]);
    $user = $stmt->fetch();
    return $user ?: null;
}

function telegram_link_code(): string {
    return strtoupper(substr(bin2hex(random_bytes(4)), 0, 8));
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

function ensure_tournament_media_table(PDO $pdo): void {
    $pdo->exec("CREATE TABLE IF NOT EXISTS tournament_media (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        tournament_id BIGINT NOT NULL,
        kind ENUM('photo', 'video') NOT NULL,
        title VARCHAR(255) NULL,
        file_path VARCHAR(512) NOT NULL,
        file_url TEXT NOT NULL,
        mime_type VARCHAR(128) NULL,
        file_size BIGINT NULL,
        uploaded_by VARCHAR(190) NULL,
        request_ip VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY idx_tournament_media_tournament (tournament_id),
        KEY idx_tournament_media_kind (kind)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
}

function ensure_app_tournament_participants_table(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS app_tournament_participants (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        tournament_id BIGINT NOT NULL,
        player_id BIGINT NULL,
        name VARCHAR(255) NOT NULL,
        city VARCHAR(255) NULL,
        challonge_participant_id BIGINT NULL,
        registered_by VARCHAR(190) NULL,
        request_ip VARCHAR(64) NULL,
        active TINYINT(1) NOT NULL DEFAULT 1,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_app_tournament_player (tournament_id, player_id),
        KEY idx_app_tournament_participants_tournament (tournament_id),
        KEY idx_app_tournament_participants_active (active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
}

function ensure_clubs_table(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS clubs (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        llb_id BIGINT UNSIGNED NULL,
        name VARCHAR(255) NOT NULL,
        city VARCHAR(255) NOT NULL,
        address VARCHAR(500) NULL,
        image_url VARCHAR(500) NULL,
        latitude DECIMAL(10,7) NULL,
        longitude DECIMAL(10,7) NULL,
        tables_pyramid INT NULL,
        tables_pool INT NULL,
        tables_snooker INT NULL,
        tables_total INT NULL,
        phone VARCHAR(128) NULL,
        website VARCHAR(500) NULL,
        created_by VARCHAR(190) NULL,
        request_ip VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_club_city_name (city, name),
        KEY idx_clubs_llb_id (llb_id),
        KEY idx_clubs_city (city)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    ensure_column($pdo, 'clubs', 'llb_id', 'BIGINT UNSIGNED NULL');
    ensure_column($pdo, 'clubs', 'image_url', 'VARCHAR(500) NULL');
    ensure_column($pdo, 'clubs', 'tables_pyramid', 'INT NULL');
    ensure_column($pdo, 'clubs', 'tables_pool', 'INT NULL');
    ensure_column($pdo, 'clubs', 'tables_snooker', 'INT NULL');
    ensure_column($pdo, 'clubs', 'tables_total', 'INT NULL');
}

function club_response_row(array $row): array {
    return [
        'id' => (string)($row['id'] ?? ''),
        'llb_id' => (string)($row['llb_id'] ?? ''),
        'name' => (string)($row['name'] ?? ''),
        'city' => (string)($row['city'] ?? ''),
        'address' => (string)($row['address'] ?? ''),
        'image_url' => (string)($row['image_url'] ?? ''),
        'latitude' => isset($row['latitude']) ? (float)$row['latitude'] : null,
        'longitude' => isset($row['longitude']) ? (float)$row['longitude'] : null,
        'tables_pyramid' => isset($row['tables_pyramid']) ? (int)$row['tables_pyramid'] : null,
        'tables_pool' => isset($row['tables_pool']) ? (int)$row['tables_pool'] : null,
        'tables_snooker' => isset($row['tables_snooker']) ? (int)$row['tables_snooker'] : null,
        'tables_total' => isset($row['tables_total']) ? (int)$row['tables_total'] : null,
        'phone' => (string)($row['phone'] ?? ''),
        'website' => (string)($row['website'] ?? ''),
        'created_by' => (string)($row['created_by'] ?? ''),
        'created_at' => (string)($row['created_at'] ?? ''),
        'tournaments_count' => isset($row['tournaments_count']) ? (int)$row['tournaments_count'] : 0,
    ];
}

function request_origin_base_url(): string {
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    $scheme = $https ? 'https' : 'http';
    $host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
    $scriptDir = rtrim(str_replace('\\', '/', dirname((string)($_SERVER['SCRIPT_NAME'] ?? ''))), '/');
    return $scheme . '://' . $host . ($scriptDir === '' ? '' : $scriptDir);
}

function public_upload_url(string $relativePath, array $config): string {
    $base = trim((string)($config['public_base_url'] ?? ''));
    if ($base === '') {
        $base = request_origin_base_url();
    }
    return rtrim($base, '/') . '/' . ltrim($relativePath, '/');
}

function uploaded_file_mime(string $path): string {
    $info = new finfo(FILEINFO_MIME_TYPE);
    return (string)($info->file($path) ?: 'application/octet-stream');
}

function media_extension(string $mimeType, string $originalName): string {
    $fromMime = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        'image/heif' => 'heif',
        'video/mp4' => 'mp4',
        'video/quicktime' => 'mov',
        'video/webm' => 'webm',
    ][$mimeType] ?? '';
    if ($fromMime !== '') {
        return $fromMime;
    }
    $ext = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
    return preg_match('/^[a-z0-9]{1,8}$/', $ext) ? $ext : 'bin';
}

function media_response_row(array $row): array {
    return [
        'id' => (string)($row['id'] ?? ''),
        'tournament_id' => (string)($row['tournament_id'] ?? ''),
        'kind' => (string)($row['kind'] ?? 'photo'),
        'title' => (string)($row['title'] ?? ''),
        'url' => (string)($row['file_url'] ?? ''),
        'file_url' => (string)($row['file_url'] ?? ''),
        'mime_type' => (string)($row['mime_type'] ?? ''),
        'file_size' => isset($row['file_size']) ? (int)$row['file_size'] : null,
        'uploaded_by' => (string)($row['uploaded_by'] ?? ''),
        'created_at' => (string)($row['created_at'] ?? ''),
    ];
}

function tournament_detail_data(array $row): array {
    $detailJson = (string)($row['detail_json'] ?? '');
    $detail = $detailJson !== '' ? json_decode($detailJson, true) : null;
    return is_array($detail) ? $detail : [];
}

function is_app_created_tournament(array $row): bool {
    $detail = tournament_detail_data($row);
    return !empty($detail['created_by_app']);
}

function tournament_internal_url(int $id): string {
    return 'https://llb.panfilius.ru/flutter_app/#/tournaments/' . $id;
}

function tournament_link_url(array $row): string {
    $compId = (int)($row['comp_id'] ?? 0);
    if ($compId > 0) {
        return 'https://t.llb.su/competition.php?comp=' . $compId;
    }
    $detail = tournament_detail_data($row);
    $challongeUrl = trim((string)($detail['challonge_url'] ?? ''));
    if ($challongeUrl !== '') {
        return $challongeUrl;
    }
    $id = (int)($row['id'] ?? 0);
    if (is_app_created_tournament($row)) {
        return tournament_internal_url($id);
    }
    return 'https://www.llb.su/t/' . $id;
}

function tournament_response_row(array $row): array {
    $compId = (int)($row['comp_id'] ?? 0);
    $id = (int)($row['id'] ?? 0);
    $detail = tournament_detail_data($row);
    return [
        'id' => (string)$id,
        'title' => (string)($row['title'] ?? 'Турнир'),
        'source_kind' => (string)($row['source_kind'] ?? 'next'),
        'status_class' => (string)($row['status_class'] ?? 'future'),
        'date_text' => (string)($row['date_text'] ?? ''),
        'city' => (string)($detail['city'] ?? ''),
        'club' => (string)($row['club'] ?? ''),
        'discipline' => (string)($detail['discipline'] ?? ''),
        'app_created' => is_app_created_tournament($row),
        'participants_count' => (int)($row['participants_count'] ?? 0),
        'participants_limit' => isset($row['participants_limit']) ? (int)$row['participants_limit'] : null,
        'comp_id' => $compId > 0 ? $compId : null,
        'matches_count' => 0,
        'bracket_url' => tournament_link_url($row),
        'participants' => [],
        'matches' => [],
        'media' => [],
    ];
}

function app_participant_response_row(array $row): array {
    return [
        'id' => (string)($row['player_id'] ?? $row['id'] ?? ''),
        'player_id' => isset($row['player_id']) ? (string)$row['player_id'] : null,
        'name' => (string)($row['name'] ?? ''),
        'city' => (string)($row['city'] ?? ''),
        'country' => 'RUS',
        'rank' => '',
        'avatar_url' => '',
        'participant_place' => '',
        'points' => '',
        'place' => '',
        'source' => 'app',
        'challonge_participant_id' => isset($row['challonge_participant_id']) ? (string)$row['challonge_participant_id'] : null,
        'registered_by' => (string)($row['registered_by'] ?? ''),
        'created_at' => (string)($row['created_at'] ?? ''),
    ];
}

function app_tournament_participants(PDO $pdo, int $tournamentId): array {
    ensure_app_tournament_participants_table($pdo);
    $stmt = $pdo->prepare('SELECT id, tournament_id, player_id, name, city, challonge_participant_id, registered_by, created_at
                           FROM app_tournament_participants
                           WHERE tournament_id = :tournament_id AND active = 1
                           ORDER BY id ASC
                           LIMIT 300');
    $stmt->execute([':tournament_id' => $tournamentId]);
    return array_map('app_participant_response_row', $stmt->fetchAll());
}

function is_online_tournament(array $tournament): bool {
    $sourceKind = strtolower((string)($tournament['source_kind'] ?? ''));
    $statusClass = strtolower((string)($tournament['status_class'] ?? ''));
    return $sourceKind === 'online' || in_array($statusClass, ['running', 'live', 'online'], true);
}

function challonge_credentials(array $config): array {
    $challonge = $config['challonge'] ?? [];
    if (!is_array($challonge)) {
        $challonge = [];
    }
    return [
        'api_key' => trim((string)($challonge['api_key'] ?? $config['challonge_api_key'] ?? '')),
        'username' => trim((string)($challonge['username'] ?? $config['challonge_username'] ?? '')),
        'client_id' => trim((string)($challonge['client_id'] ?? $config['challonge_client_id'] ?? '')),
        'client_secret' => trim((string)($challonge['client_secret'] ?? $config['challonge_client_secret'] ?? '')),
        'base_url' => rtrim((string)($challonge['base_url'] ?? 'https://api.challonge.com/v2.1'), '/'),
        'token_url' => (string)($challonge['token_url'] ?? 'https://api.challonge.com/oauth/token'),
    ];
}

function challonge_slug(string $title, int $id): string {
    $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $title);
    $base = strtolower((string)($ascii ?: $title));
    $base = preg_replace('/[^a-z0-9]+/', '_', $base) ?? '';
    $base = trim($base, '_');
    if ($base === '') {
        $base = 'llb_tournament';
    }
    $suffix = '_' . $id;
    $maxBaseLength = max(1, 48 - strlen($suffix));
    return substr($base, 0, $maxBaseLength) . $suffix;
}

function http_json_post(string $url, array $headers, string $body, int $timeout = 15): array {
    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'timeout' => $timeout,
            'ignore_errors' => true,
            'header' => implode("\r\n", $headers) . "\r\n",
            'content' => $body,
        ],
    ]);
    $responseBody = @file_get_contents($url, false, $context);
    $status = 0;
    foreach (($http_response_header ?? []) as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $m)) {
            $status = (int)$m[1];
            break;
        }
    }
    $data = is_string($responseBody) && $responseBody !== '' ? json_decode($responseBody, true) : null;
    return ['status' => $status, 'body' => is_string($responseBody) ? $responseBody : '', 'json' => is_array($data) ? $data : []];
}

function http_json_request(string $method, string $url, array $headers, string $body = '', int $timeout = 15): array {
    $options = [
        'method' => $method,
        'timeout' => $timeout,
        'ignore_errors' => true,
        'header' => implode("\r\n", $headers) . "\r\n",
    ];
    if ($body !== '') {
        $options['content'] = $body;
    }
    $context = stream_context_create(['http' => $options]);
    $responseBody = @file_get_contents($url, false, $context);
    $status = 0;
    foreach (($http_response_header ?? []) as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $m)) {
            $status = (int)$m[1];
            break;
        }
    }
    $data = is_string($responseBody) && $responseBody !== '' ? json_decode($responseBody, true) : null;
    return ['status' => $status, 'body' => is_string($responseBody) ? $responseBody : '', 'json' => is_array($data) ? $data : []];
}

function challonge_access_token(array $config): string {
    $credentials = challonge_credentials($config);
    if ($credentials['client_id'] === '' || $credentials['client_secret'] === '') {
        throw new RuntimeException('challonge_credentials_missing');
    }
    $response = http_json_post(
        $credentials['token_url'],
        [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'User-Agent: llb-mobile-backend/1.0',
        ],
        http_build_query([
            'grant_type' => 'client_credentials',
            'client_id' => $credentials['client_id'],
            'client_secret' => $credentials['client_secret'],
            'scope' => 'application:manage',
        ])
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        throw new RuntimeException('challonge_token_http_' . $response['status']);
    }
    $token = (string)($response['json']['access_token'] ?? '');
    if ($token === '') {
        throw new RuntimeException('challonge_token_missing');
    }
    return $token;
}

function challonge_create_tournament(array $config, int $id, string $title, string $discipline, string $dateText, string $tournamentType): array {
    $credentials = challonge_credentials($config);
    if ($credentials['username'] !== '' && $credentials['api_key'] !== '') {
        return challonge_create_tournament_v1($credentials['username'], $credentials['api_key'], $id, $title, $discipline, $dateText, $tournamentType);
    }
    $token = challonge_access_token($config);
    $slug = challonge_slug($title, $id);
    $response = http_json_post(
        $credentials['base_url'] . '/tournaments.json',
        [
            'Accept: application/json',
            'Content-Type: application/vnd.api+json',
            'Authorization: Bearer ' . $token,
            'User-Agent: llb-mobile-backend/1.0',
        ],
        json_encode([
            'data' => [
                'type' => 'tournament',
                'attributes' => [
                    'name' => $title,
                    'url' => $slug,
                    'tournament_type' => $tournamentType,
                    'game_name' => $discipline !== '' ? $discipline : 'Billiards',
                    'private' => true,
                    'description' => 'Created from LLB mobile app. Date: ' . $dateText,
                    'notifications' => [
                        'upon_matches_open' => true,
                        'upon_tournament_ends' => true,
                    ],
                    'registration_options' => ['open_signup' => false],
                ],
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        throw new RuntimeException('challonge_create_http_' . $response['status']);
    }
    $data = $response['json']['data'] ?? [];
    $attributes = is_array($data) && isset($data['attributes']) && is_array($data['attributes'])
        ? $data['attributes']
        : [];
    $url = (string)($attributes['url'] ?? $slug);
    return [
        'id' => (string)($data['id'] ?? ''),
        'slug' => $slug,
        'url' => preg_match('/^https?:\/\//i', $url) ? $url : 'https://challonge.com/' . $url,
    ];
}

function challonge_create_tournament_v1(string $username, string $apiKey, int $id, string $title, string $discipline, string $dateText, string $tournamentType): array {
    $slug = challonge_slug($title, $id);
    $response = http_json_post(
        'https://api.challonge.com/v1/tournaments.json',
        [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'Authorization: Basic ' . base64_encode($username . ':' . $apiKey),
            'User-Agent: llb-mobile-backend/1.0',
        ],
        http_build_query([
            'tournament[name]' => $title,
            'tournament[url]' => $slug,
            'tournament[tournament_type]' => $tournamentType,
            'tournament[game_name]' => $discipline !== '' ? $discipline : 'Billiards',
            'tournament[private]' => 'true',
            'tournament[description]' => 'Created from LLB mobile app. Date: ' . $dateText,
            'tournament[open_signup]' => 'false',
        ])
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        $error = 'challonge_v1_create_http_' . $response['status'];
        $body = trim($response['body']);
        if ($body !== '') {
            $error .= ': ' . substr($body, 0, 300);
        }
        throw new RuntimeException($error);
    }
    $tournament = $response['json']['tournament'] ?? [];
    if (!is_array($tournament)) {
        $tournament = [];
    }
    $url = (string)($tournament['full_challonge_url'] ?? $tournament['url'] ?? $slug);
    return [
        'id' => (string)($tournament['id'] ?? ''),
        'slug' => $slug,
        'url' => preg_match('/^https?:\/\//i', $url) ? $url : 'https://challonge.com/' . $url,
    ];
}

function challonge_tournament_identifier(array $tournament): string {
    $detail = tournament_detail_data($tournament);
    $id = trim((string)($detail['challonge_id'] ?? ''));
    if ($id !== '') {
        return $id;
    }
    return trim((string)($detail['challonge_slug'] ?? ''));
}

function challonge_error_message(string $prefix, array $response): string {
    $message = $prefix . $response['status'];
    $body = trim((string)($response['body'] ?? ''));
    if ($body !== '') {
        $message .= ': ' . substr($body, 0, 300);
    }
    return $message;
}

function challonge_create_participant(array $config, array $tournament, string $name, ?int $playerId): array {
    $credentials = challonge_credentials($config);
    $identifier = challonge_tournament_identifier($tournament);
    if ($identifier === '' || $credentials['username'] === '' || $credentials['api_key'] === '') {
        return [];
    }
    $response = http_json_post(
        'https://api.challonge.com/v1/tournaments/' . rawurlencode($identifier) . '/participants.json',
        [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'Authorization: Basic ' . base64_encode($credentials['username'] . ':' . $credentials['api_key']),
            'User-Agent: llb-mobile-backend/1.0',
        ],
        http_build_query([
            'participant[name]' => $name,
            'participant[misc]' => $playerId && $playerId > 0 ? 'llb_player_id:' . $playerId : '',
        ])
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        throw new RuntimeException(challonge_error_message('challonge_participant_create_http_', $response));
    }
    $participant = $response['json']['participant'] ?? [];
    return is_array($participant) ? $participant : [];
}

function challonge_delete_participant(array $config, array $tournament, int $participantId): void {
    $credentials = challonge_credentials($config);
    $identifier = challonge_tournament_identifier($tournament);
    if ($identifier === '' || $participantId <= 0 || $credentials['username'] === '' || $credentials['api_key'] === '') {
        return;
    }
    $context = stream_context_create([
        'http' => [
            'method' => 'DELETE',
            'timeout' => 15,
            'ignore_errors' => true,
            'header' => implode("\r\n", [
                'Accept: application/json',
                'Authorization: Basic ' . base64_encode($credentials['username'] . ':' . $credentials['api_key']),
                'User-Agent: llb-mobile-backend/1.0',
            ]) . "\r\n",
        ],
    ]);
    $responseBody = @file_get_contents(
        'https://api.challonge.com/v1/tournaments/' . rawurlencode($identifier) . '/participants/' . rawurlencode((string)$participantId) . '.json',
        false,
        $context
    );
    $status = 0;
    foreach (($http_response_header ?? []) as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $m)) {
            $status = (int)$m[1];
            break;
        }
    }
    if ($status < 200 || $status >= 300) {
        throw new RuntimeException(challonge_error_message('challonge_participant_delete_http_', [
            'status' => $status,
            'body' => is_string($responseBody) ? $responseBody : '',
        ]));
    }
}

function challonge_matches(array $config, array $tournament): array {
    $credentials = challonge_credentials($config);
    $identifier = challonge_tournament_identifier($tournament);
    if ($identifier === '' || $credentials['username'] === '' || $credentials['api_key'] === '') {
        return [];
    }
    $response = http_json_request(
        'GET',
        'https://api.challonge.com/v1/tournaments/' . rawurlencode($identifier) . '/matches.json',
        [
            'Accept: application/json',
            'Authorization: Basic ' . base64_encode($credentials['username'] . ':' . $credentials['api_key']),
            'User-Agent: llb-mobile-backend/1.0',
        ]
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        throw new RuntimeException(challonge_error_message('challonge_matches_http_', $response));
    }
    return is_array($response['json']) ? $response['json'] : [];
}

function challonge_update_match_score(array $config, array $tournament, int $matchId, string $scoresCsv, int $winnerId): array {
    $credentials = challonge_credentials($config);
    $identifier = challonge_tournament_identifier($tournament);
    if ($identifier === '' || $matchId <= 0 || $scoresCsv === '' || $winnerId <= 0 || $credentials['username'] === '' || $credentials['api_key'] === '') {
        throw new RuntimeException('challonge_match_score_missing_data');
    }
    $response = http_json_request(
        'PUT',
        'https://api.challonge.com/v1/tournaments/' . rawurlencode($identifier) . '/matches/' . rawurlencode((string)$matchId) . '.json',
        [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'Authorization: Basic ' . base64_encode($credentials['username'] . ':' . $credentials['api_key']),
            'User-Agent: llb-mobile-backend/1.0',
        ],
        http_build_query([
            'match[scores_csv]' => $scoresCsv,
            'match[winner_id]' => $winnerId,
        ])
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        throw new RuntimeException(challonge_error_message('challonge_match_score_http_', $response));
    }
    $match = $response['json']['match'] ?? [];
    return is_array($match) ? $match : [];
}

function challonge_match_response(array $match, int $myParticipantId, string $myName): array {
    $player1Id = (int)($match['player1_id'] ?? 0);
    $player2Id = (int)($match['player2_id'] ?? 0);
    $mySlot = $player1Id === $myParticipantId ? 1 : 2;
    $state = (string)($match['state'] ?? '');
    return [
        'id' => (string)($match['id'] ?? ''),
        'state' => $state,
        'round' => (string)($match['round'] ?? ''),
        'identifier' => (string)($match['identifier'] ?? ''),
        'player1_id' => $player1Id > 0 ? (string)$player1Id : null,
        'player2_id' => $player2Id > 0 ? (string)$player2Id : null,
        'my_participant_id' => (string)$myParticipantId,
        'my_slot' => $mySlot,
        'my_name' => $myName,
        'opponent_participant_id' => $mySlot === 1 ? (string)$player2Id : (string)$player1Id,
        'scores_csv' => (string)($match['scores_csv'] ?? ''),
        'winner_id' => isset($match['winner_id']) ? (string)$match['winner_id'] : null,
        'underway_at' => (string)($match['underway_at'] ?? ''),
        'started_at' => (string)($match['started_at'] ?? ''),
    ];
}

function player_in_tournament(PDO $pdo, int $tournamentId, int $playerId): bool {
    $stmt = $pdo->prepare('SELECT comp_id, detail_json FROM tournaments WHERE id = ?');
    $stmt->execute([$tournamentId]);
    $tournament = $stmt->fetch();
    if (!$tournament) {
        return false;
    }
    if (is_app_created_tournament($tournament)) {
        ensure_app_tournament_participants_table($pdo);
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM app_tournament_participants WHERE tournament_id = ? AND player_id = ? AND active = 1');
        $stmt->execute([$tournamentId, $playerId]);
        return (int)$stmt->fetchColumn() > 0;
    }
    $compId = (int)($tournament['comp_id'] ?? 0);
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

function telegram_bot_token(array $config): string {
    return trim((string)($config['telegram_bot_token'] ?? ''));
}

function telegram_send_message(string $token, int $chatId, string $text): void {
    if ($token === '' || $chatId <= 0) {
        return;
    }
    http_json_post(
        'https://api.telegram.org/bot' . $token . '/sendMessage',
        [
            'Accept: application/json',
            'Content-Type: application/json',
            'User-Agent: llb-mobile-bot/1.0',
        ],
        json_encode([
            'chat_id' => $chatId,
            'text' => $text,
            'disable_web_page_preview' => true,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    );
}

function telegram_respond_message(int $chatId, string $text): void {
    respond([
        'method' => 'sendMessage',
        'chat_id' => $chatId,
        'text' => $text,
        'disable_web_page_preview' => true,
    ]);
}

function telegram_help_text(): string {
    return implode("\n", [
        'Лига бильярдистов',
        '',
        '/tournaments - ближайшие турниры',
        '/create Название | Город | Клуб | 25.07.26 19:00 | Пул | 32',
        '/join 5500001 Иван Петров',
    ]);
}

function telegram_upcoming_text(PDO $pdo): string {
    $stmt = $pdo->query('SELECT id, title, date_text, club
        FROM tournaments
        WHERE (source_kind = "next" OR status_class = "future")
          AND LOWER(date_text) NOT LIKE "%отмен%"
          AND COALESCE(
              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(date_text, "\n", " "), " ", 1), "%d.%m.%y"),
              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(date_text, "\n", " "), " ", 1), "%d.%m.%Y")
          ) >= CURDATE()
        ORDER BY COALESCE(
              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(date_text, "\n", " "), " ", 1), "%d.%m.%y"),
              STR_TO_DATE(SUBSTRING_INDEX(REPLACE(date_text, "\n", " "), " ", 1), "%d.%m.%Y")
          ) ASC, id DESC
        LIMIT 8');
    $rows = $stmt->fetchAll();
    if (!$rows) {
        return 'Ближайших турниров пока нет.';
    }
    $lines = ['Ближайшие турниры:'];
    foreach ($rows as $row) {
        $club = trim((string)($row['club'] ?? ''));
        $lines[] = sprintf(
            "%s. %s\n%s%s\nhttps://llb.panfilius.ru/flutter_app/",
            (string)$row['id'],
            (string)$row['title'],
            str_replace("\n", ' ', (string)$row['date_text']),
            $club !== '' ? ' · ' . $club : ''
        );
    }
    return implode("\n\n", $lines);
}

function telegram_create_tournament(array $config, string $text, string $createdBy): string {
    $payload = trim(preg_replace('/^\/create(@\w+)?/iu', '', $text) ?? '');
    $parts = array_map('trim', explode('|', $payload));
    if (count($parts) < 5) {
        return telegram_help_text();
    }
    $capacity = isset($parts[5]) ? (int)$parts[5] : 32;
    $response = http_json_post(
        'https://llb.panfilius.ru/llb-api/?resource=tournament_create',
        [
            'Accept: application/json',
            'Content-Type: application/json',
            'User-Agent: llb-mobile-bot/1.0',
        ],
        json_encode([
            'title' => $parts[0],
            'city' => $parts[1],
            'club' => $parts[2],
            'date_text' => $parts[3],
            'discipline' => $parts[4],
            'participants_limit' => $capacity > 0 ? $capacity : 32,
            'tournament_type' => 'single elimination',
            'created_by' => $createdBy,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    );
    if ($response['status'] < 200 || $response['status'] >= 300 || empty($response['json']['item'])) {
        return 'Не удалось создать турнир. Проверьте формат команды.';
    }
    $item = $response['json']['item'];
    return 'Турнир создан: ' . (string)($item['title'] ?? $parts[0]) . "\nID: " . (string)($item['id'] ?? '');
}

function telegram_join_tournament(string $text, int $telegramUserId, string $telegramName): string {
    $payload = trim(preg_replace('/^\/join(@\w+)?/iu', '', $text) ?? '');
    if (!preg_match('/^(\d+)\s*(.*)$/u', $payload, $matches)) {
        return 'Напишите так: /join 5500001 Иван Петров';
    }
    $name = trim($matches[2] ?: $telegramName);
    if ($name === '') {
        $name = 'Telegram user ' . $telegramUserId;
    }
    $response = http_json_post(
        'https://llb.panfilius.ru/llb-api/?resource=tournament_registration',
        [
            'Accept: application/json',
            'Content-Type: application/json',
            'User-Agent: llb-mobile-bot/1.0',
        ],
        json_encode([
            'tournament_id' => (int)$matches[1],
            'action' => 'register',
            'username' => 'telegram:' . $telegramUserId,
            'name' => $name,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        return 'Не удалось записаться. Возможно, этот турнир не создан в приложении.';
    }
    return 'Запись сохранена: ' . $name;
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
    if ($resource === 'telegram_bot') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['ok' => true, 'message' => 'telegram webhook']);
        }
        $update = json_body();
        $message = is_array($update['message'] ?? null) ? $update['message'] : [];
        $chat = is_array($message['chat'] ?? null) ? $message['chat'] : [];
        $from = is_array($message['from'] ?? null) ? $message['from'] : [];
        $chatId = (int)($chat['id'] ?? 0);
        $text = trim((string)($message['text'] ?? ''));
        $telegramUserId = (int)($from['id'] ?? 0);
        $telegramName = trim(implode(' ', array_filter([
            (string)($from['first_name'] ?? ''),
            (string)($from['last_name'] ?? ''),
        ])));
        if ($chatId > 0) {
            if (preg_match('/^\/tournaments(@\w+)?/iu', $text)) {
                telegram_respond_message($chatId, telegram_upcoming_text($pdo));
            } elseif (preg_match('/^\/create(@\w+)?/iu', $text)) {
                telegram_respond_message(
                    $chatId,
                    telegram_create_tournament($config, $text, 'telegram:' . $telegramUserId)
                );
            } elseif (preg_match('/^\/join(@\w+)?/iu', $text)) {
                telegram_respond_message(
                    $chatId,
                    telegram_join_tournament($text, $telegramUserId, $telegramName)
                );
            } else {
                telegram_respond_message($chatId, telegram_help_text());
            }
        }
        respond(['ok' => true]);
    }

    if ($resource === 'app_config') {
        respond([
            'ok' => true,
            'mapbox_access_token' => (string)($config['mapbox_access_token'] ?? ''),
        ]);
    }

    if ($resource === 'telegram_link_start') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_telegram_links_table($pdo);
        $body = json_body();
        $telegramId = (int)($body['telegram_id'] ?? 0);
        $chatId = (int)($body['chat_id'] ?? 0);
        if ($telegramId <= 0 || $chatId === 0) {
            respond(['error' => 'telegram_id_required'], 400);
        }
        $code = telegram_link_code();
        $codeHash = hash('sha256', $code);
        $stmt = $pdo->prepare('DELETE FROM telegram_links WHERE telegram_id = ? AND claimed_at IS NULL');
        $stmt->execute([$telegramId]);
        $stmt = $pdo->prepare('INSERT INTO telegram_links
              (code_hash, telegram_id, telegram_username, telegram_first_name, telegram_last_name, chat_id, expires_at)
              VALUES (:code_hash, :telegram_id, :telegram_username, :telegram_first_name, :telegram_last_name, :chat_id, DATE_ADD(NOW(), INTERVAL 20 MINUTE))');
        $stmt->execute([
            ':code_hash' => $codeHash,
            ':telegram_id' => $telegramId,
            ':telegram_username' => trim((string)($body['telegram_username'] ?? '')) ?: null,
            ':telegram_first_name' => trim((string)($body['first_name'] ?? '')) ?: null,
            ':telegram_last_name' => trim((string)($body['last_name'] ?? '')) ?: null,
            ':chat_id' => $chatId,
        ]);
        respond([
            'ok' => true,
            'code' => $code,
            'expires_in' => 1200,
            'link_url' => 'https://llb.panfilius.ru/open/telegram-link/?code=' . rawurlencode($code),
            'app_url' => 'llb://telegram-link/' . rawurlencode($code),
        ], 201);
    }

    if ($resource === 'telegram_link_claim') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_telegram_links_table($pdo);
        $body = json_body();
        $code = strtoupper(trim((string)($body['code'] ?? '')));
        $token = trim((string)($body['token'] ?? ''));
        if (!preg_match('/^[A-F0-9]{8}$/', $code)) {
            respond(['error' => 'bad_code'], 400);
        }
        $user = app_user_by_token($pdo, $token);
        if (!$user) {
            respond(['error' => 'bad_token'], 401);
        }
        $stmt = $pdo->prepare('SELECT * FROM telegram_links WHERE code_hash = ? AND claimed_at IS NULL AND expires_at > NOW() LIMIT 1');
        $stmt->execute([hash('sha256', $code)]);
        $link = $stmt->fetch();
        if (!$link) {
            respond(['error' => 'link_not_found_or_expired'], 404);
        }
        $pdo->beginTransaction();
        try {
            $stmt = $pdo->prepare('UPDATE app_users
                                   SET telegram_id = NULL,
                                       telegram_username = NULL,
                                       telegram_chat_id = NULL,
                                       telegram_linked_at = NULL
                                   WHERE telegram_id = ? AND id <> ?');
            $stmt->execute([(int)$link['telegram_id'], (int)$user['id']]);
            $stmt = $pdo->prepare('UPDATE app_users
                                   SET telegram_id = :telegram_id,
                                       telegram_username = :telegram_username,
                                       telegram_chat_id = :telegram_chat_id,
                                       telegram_linked_at = NOW(),
                                       updated_at = NOW()
                                   WHERE id = :id');
            $stmt->execute([
                ':telegram_id' => (int)$link['telegram_id'],
                ':telegram_username' => $link['telegram_username'] ?: null,
                ':telegram_chat_id' => (int)$link['chat_id'],
                ':id' => (int)$user['id'],
            ]);
            $stmt = $pdo->prepare('UPDATE telegram_links SET app_user_id = ?, claimed_at = NOW() WHERE code_hash = ?');
            $stmt->execute([(int)$user['id'], hash('sha256', $code)]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        $stmt = $pdo->prepare('SELECT * FROM app_users WHERE id = ?');
        $stmt->execute([(int)$user['id']]);
        respond(['ok' => true, 'user' => app_user_response($stmt->fetch() ?: [])]);
    }

    if ($resource === 'telegram_me') {
        ensure_app_users_table($pdo);
        $telegramId = (int)($_GET['telegram_id'] ?? 0);
        if ($telegramId <= 0) {
            respond(['error' => 'telegram_id_required'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM app_users WHERE telegram_id = ? LIMIT 1');
        $stmt->execute([$telegramId]);
        $user = $stmt->fetch();
        if (!$user) {
            respond(['ok' => true, 'linked' => false]);
        }
        respond(['ok' => true, 'linked' => true, 'user' => app_user_response($user)]);
    }

    if ($resource === 'app_auth') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_app_users_table($pdo);
        $body = json_body();
        $action = (string)($body['action'] ?? 'login');
        $username = trim((string)($body['username'] ?? ''));
        $password = (string)($body['password'] ?? '');
        $displayName = trim((string)($body['display_name'] ?? $username));
        $city = trim((string)($body['city'] ?? ''));
        if (!in_array($action, ['register', 'login'], true)) {
            respond(['error' => 'bad_action'], 400);
        }
        if ($username === '' || $password === '') {
            respond(['error' => 'credentials_required'], 400);
        }
        if (mb_strlen($username) > 190 || mb_strlen($displayName) > 255 || mb_strlen($city) > 255 || strlen($password) > 1024) {
            respond(['error' => 'credentials_too_long'], 400);
        }
        if ($action === 'register' && strlen($password) < 6) {
            respond(['error' => 'password_too_short'], 400);
        }
        $usernameHash = hash('sha256', mb_strtolower($username));
        $stmt = $pdo->prepare('SELECT * FROM app_users WHERE username_hash = ? LIMIT 1');
        $stmt->execute([$usernameHash]);
        $user = $stmt->fetch();
        if ($action === 'register') {
            if ($user) {
                respond(['error' => 'username_taken'], 409);
            }
            $passwordHash = password_hash($password, PASSWORD_DEFAULT);
            $token = bin2hex(random_bytes(32));
            $tokenHash = hash('sha256', $token);
            $stmt = $pdo->prepare('INSERT INTO app_users
                  (username, username_hash, display_name, city, password_hash, auth_token_hash, request_ip, user_agent, last_login_at)
                  VALUES (:username, :username_hash, :display_name, :city, :password_hash, :auth_token_hash, :request_ip, :user_agent, NOW())');
            $stmt->execute([
                ':username' => $username,
                ':username_hash' => $usernameHash,
                ':display_name' => $displayName !== '' ? $displayName : $username,
                ':city' => $city,
                ':password_hash' => $passwordHash,
                ':auth_token_hash' => $tokenHash,
                ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
                ':user_agent' => substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255),
            ]);
            $stmt = $pdo->prepare('SELECT * FROM app_users WHERE id = ?');
            $stmt->execute([(int)$pdo->lastInsertId()]);
            respond(['ok' => true, 'user' => app_user_response($stmt->fetch() ?: [], $token)], 201);
        }
        if (!$user || !password_verify($password, (string)($user['password_hash'] ?? ''))) {
            respond(['error' => 'bad_credentials'], 401);
        }
        $token = bin2hex(random_bytes(32));
        $tokenHash = hash('sha256', $token);
        $stmt = $pdo->prepare('UPDATE app_users
                               SET auth_token_hash = :auth_token_hash,
                                   request_ip = :request_ip,
                                   user_agent = :user_agent,
                                   last_login_at = NOW(),
                                   updated_at = NOW()
                               WHERE id = :id');
        $stmt->execute([
            ':auth_token_hash' => $tokenHash,
            ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
            ':user_agent' => substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255),
            ':id' => (int)$user['id'],
        ]);
        $user['auth_token_hash'] = $tokenHash;
        respond(['ok' => true, 'user' => app_user_response($user, $token)]);
    }

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
        try {
            ensure_tournament_media_table($pdo);
            $counts['tournament_media'] = (int)$pdo->query('SELECT COUNT(*) FROM tournament_media')->fetchColumn();
        } catch (Throwable $ignored) {
            $counts['tournament_media'] = 0;
        }
        respond(['ok' => true, 'counts' => $counts]);
    }

    if ($resource === 'clubs') {
        ensure_clubs_table($pdo);
        if ($_SERVER['REQUEST_METHOD'] === 'POST') {
            $body = json_body();
            $name = trim((string)($body['name'] ?? ''));
            $city = trim((string)($body['city'] ?? ''));
            $address = trim((string)($body['address'] ?? ''));
            $phone = trim((string)($body['phone'] ?? ''));
            $website = trim((string)($body['website'] ?? ''));
            $createdBy = trim((string)($body['created_by'] ?? ''));
            $llbId = $body['llb_id'] ?? null;
            $imageUrl = trim((string)($body['image_url'] ?? ''));
            $tablesPyramid = $body['tables_pyramid'] ?? null;
            $tablesPool = $body['tables_pool'] ?? null;
            $tablesSnooker = $body['tables_snooker'] ?? null;
            $tablesTotal = $body['tables_total'] ?? null;
            $latitude = $body['latitude'] ?? null;
            $longitude = $body['longitude'] ?? null;
            if ($name === '' || $city === '') {
                respond(['error' => 'name_and_city_required'], 400);
            }
            if (mb_strlen($name) > 255 || mb_strlen($city) > 255 || mb_strlen($address) > 500 || mb_strlen($phone) > 128 || mb_strlen($website) > 500 || mb_strlen($imageUrl) > 500) {
                respond(['error' => 'value_too_long'], 400);
            }
            $llbIdValue = is_numeric($llbId) ? (int)$llbId : null;
            $latValue = is_numeric($latitude) ? (float)$latitude : null;
            $lngValue = is_numeric($longitude) ? (float)$longitude : null;
            $tablesPyramidValue = is_numeric($tablesPyramid) ? (int)$tablesPyramid : null;
            $tablesPoolValue = is_numeric($tablesPool) ? (int)$tablesPool : null;
            $tablesSnookerValue = is_numeric($tablesSnooker) ? (int)$tablesSnooker : null;
            $tablesTotalValue = is_numeric($tablesTotal) ? (int)$tablesTotal : null;
            if (($latValue !== null && ($latValue < -90 || $latValue > 90)) || ($lngValue !== null && ($lngValue < -180 || $lngValue > 180))) {
                respond(['error' => 'bad_coordinates'], 400);
            }
            $stmt = $pdo->prepare('INSERT INTO clubs
                  (llb_id, name, city, address, image_url, latitude, longitude, tables_pyramid, tables_pool, tables_snooker, tables_total, phone, website, created_by, request_ip)
                  VALUES (:llb_id, :name, :city, :address, :image_url, :latitude, :longitude, :tables_pyramid, :tables_pool, :tables_snooker, :tables_total, :phone, :website, :created_by, :request_ip)
                  ON DUPLICATE KEY UPDATE
                    llb_id = VALUES(llb_id),
                    address = VALUES(address),
                    image_url = VALUES(image_url),
                    latitude = VALUES(latitude),
                    longitude = VALUES(longitude),
                    tables_pyramid = VALUES(tables_pyramid),
                    tables_pool = VALUES(tables_pool),
                    tables_snooker = VALUES(tables_snooker),
                    tables_total = VALUES(tables_total),
                    phone = VALUES(phone),
                    website = VALUES(website),
                    created_by = VALUES(created_by),
                    request_ip = VALUES(request_ip),
                    updated_at = NOW()');
            $stmt->execute([
                ':llb_id' => $llbIdValue,
                ':name' => $name,
                ':city' => $city,
                ':address' => $address,
                ':image_url' => $imageUrl,
                ':latitude' => $latValue,
                ':longitude' => $lngValue,
                ':tables_pyramid' => $tablesPyramidValue,
                ':tables_pool' => $tablesPoolValue,
                ':tables_snooker' => $tablesSnookerValue,
                ':tables_total' => $tablesTotalValue,
                ':phone' => $phone,
                ':website' => $website,
                ':created_by' => $createdBy,
                ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
            ]);
            $stmt = $pdo->prepare('SELECT c.*,
                                          (SELECT COUNT(*) FROM tournaments t WHERE t.club = c.name AND JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.city")) = c.city) AS tournaments_count
                                   FROM clubs c
                                   WHERE c.city = :city AND c.name = :name
                                   LIMIT 1');
            $stmt->execute([':city' => $city, ':name' => $name]);
            respond(['ok' => true, 'item' => club_response_row($stmt->fetch() ?: [])], 201);
        }
        if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        $city = trim((string)($_GET['city'] ?? ''));
        $q = trim((string)($_GET['q'] ?? ''));
        $where = [];
        $params = [];
        if ($city !== '') {
            $where[] = 'c.city = :city';
            $params[':city'] = $city;
        }
        if ($q !== '') {
            $where[] = '(c.name LIKE :q OR c.city LIKE :q OR c.address LIKE :q)';
            $params[':q'] = '%' . $q . '%';
        }
        $sql = 'SELECT c.*,
                       (SELECT COUNT(*) FROM tournaments t WHERE t.club = c.name AND JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.city")) = c.city) AS tournaments_count
                FROM clubs c';
        if ($where) {
            $sql .= ' WHERE ' . implode(' AND ', $where);
        }
        $clubLimit = int_param('limit', 1000, 1, 3000);
        $sql .= ' ORDER BY c.city ASC, c.name ASC LIMIT :limit OFFSET :offset';
        $stmt = $pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, PDO::PARAM_STR);
        }
        $stmt->bindValue(':limit', $clubLimit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        respond(['items' => array_map('club_response_row', $stmt->fetchAll()), 'limit' => $clubLimit, 'offset' => $offset]);
    }

    if ($resource === 'tournament_media') {
        ensure_tournament_media_table($pdo);
        if ($_SERVER['REQUEST_METHOD'] === 'GET') {
            $tournamentId = (int)($_GET['tournament_id'] ?? 0);
            if ($tournamentId <= 0) {
                respond(['error' => 'tournament_id_required'], 400);
            }
            $stmt = $pdo->prepare('SELECT * FROM tournament_media
                                   WHERE tournament_id = :tournament_id
                                   ORDER BY id DESC
                                   LIMIT :limit OFFSET :offset');
            $stmt->bindValue(':tournament_id', $tournamentId, PDO::PARAM_INT);
            $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
            $stmt->execute();
            respond([
                'items' => array_map('media_response_row', $stmt->fetchAll()),
                'limit' => $limit,
                'offset' => $offset,
            ]);
        }
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }

        $tournamentId = (int)($_POST['tournament_id'] ?? 0);
        $kind = strtolower(trim((string)($_POST['kind'] ?? 'photo')));
        $title = trim((string)($_POST['title'] ?? ''));
        $uploadedBy = trim((string)($_POST['uploaded_by'] ?? ''));
        if ($tournamentId <= 0 || !in_array($kind, ['photo', 'video'], true)) {
            respond(['error' => 'bad_media_request'], 400);
        }
        $stmt = $pdo->prepare('SELECT id FROM tournaments WHERE id = ?');
        $stmt->execute([$tournamentId]);
        if (!$stmt->fetchColumn()) {
            respond(['error' => 'tournament_not_found'], 404);
        }
        if (empty($_FILES['file']) || !is_array($_FILES['file'])) {
            respond(['error' => 'file_required'], 400);
        }
        $file = $_FILES['file'];
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            respond(['error' => 'upload_failed'], 400);
        }
        $tmpName = (string)($file['tmp_name'] ?? '');
        $size = (int)($file['size'] ?? 0);
        if ($tmpName === '' || $size <= 0 || $size > 512 * 1024 * 1024) {
            respond(['error' => 'bad_file_size'], 400);
        }
        $mimeType = uploaded_file_mime($tmpName);
        $isAllowed = $kind === 'photo'
            ? in_array($mimeType, ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'], true)
            : in_array($mimeType, ['video/mp4', 'video/quicktime', 'video/webm'], true);
        if (!$isAllowed) {
            respond(['error' => 'bad_file_type', 'mime_type' => $mimeType], 415);
        }

        $relativeDir = 'uploads/tournament_media/' . $tournamentId;
        $targetDir = __DIR__ . '/' . $relativeDir;
        if (!is_dir($targetDir) && !mkdir($targetDir, 0775, true) && !is_dir($targetDir)) {
            respond(['error' => 'upload_dir_failed'], 500);
        }
        $extension = media_extension($mimeType, (string)($file['name'] ?? ''));
        $basename = date('YmdHis') . '-' . bin2hex(random_bytes(8)) . '.' . $extension;
        $targetPath = $targetDir . '/' . $basename;
        if (!move_uploaded_file($tmpName, $targetPath)) {
            respond(['error' => 'file_save_failed'], 500);
        }
        $relativePath = $relativeDir . '/' . $basename;
        $fileUrl = public_upload_url($relativePath, $config);
        if ($title === '') {
            $title = (string)($file['name'] ?? '');
        }

        $stmt = $pdo->prepare('INSERT INTO tournament_media
              (tournament_id, kind, title, file_path, file_url, mime_type, file_size, uploaded_by, request_ip)
              VALUES (:tournament_id, :kind, :title, :file_path, :file_url, :mime_type, :file_size, :uploaded_by, :request_ip)');
        $stmt->execute([
            ':tournament_id' => $tournamentId,
            ':kind' => $kind,
            ':title' => mb_substr($title, 0, 255),
            ':file_path' => $relativePath,
            ':file_url' => $fileUrl,
            ':mime_type' => $mimeType,
            ':file_size' => $size,
            ':uploaded_by' => $uploadedBy !== '' ? mb_substr($uploadedBy, 0, 190) : null,
            ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? null,
        ]);
        $id = (int)$pdo->lastInsertId();
        $stmt = $pdo->prepare('SELECT * FROM tournament_media WHERE id = ?');
        $stmt->execute([$id]);
        respond(['ok' => true, 'item' => media_response_row($stmt->fetch() ?: [])], 201);
    }

    if ($resource === 'tournament_create') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        $body = json_body();
        $title = trim((string)($body['title'] ?? ''));
        $city = trim((string)($body['city'] ?? ''));
        $club = trim((string)($body['club'] ?? ''));
        $dateText = trim((string)($body['date_text'] ?? ''));
        $discipline = trim((string)($body['discipline'] ?? 'Пирамида'));
        $tournamentType = trim((string)($body['tournament_type'] ?? 'single elimination'));
        $capacity = (int)($body['participants_limit'] ?? 0);
        $createdBy = trim((string)($body['created_by'] ?? ''));
        if ($title === '') {
            respond(['error' => 'title_required'], 400);
        }
        if (mb_strlen($title) > 500 || mb_strlen($club) > 255 || mb_strlen($dateText) > 255) {
            respond(['error' => 'value_too_long'], 400);
        }
        if ($capacity < 0 || $capacity > 512) {
            respond(['error' => 'bad_capacity'], 400);
        }
        $allowedTournamentTypes = ['single elimination', 'double elimination', 'round robin', 'swiss'];
        if (!in_array($tournamentType, $allowedTournamentTypes, true)) {
            respond(['error' => 'bad_tournament_type'], 400);
        }

        $nextId = (int)$pdo->query('SELECT COALESCE(MAX(id), 5500000) + 1 FROM tournaments')->fetchColumn();
        $now = date(DATE_ATOM);
        $detail = [
            'created_by_app' => true,
            'created_by' => $createdBy,
            'city' => $city,
            'discipline' => $discipline,
            'tournament_type' => $tournamentType,
        ];
        try {
            $challonge = challonge_create_tournament($config, $nextId, $title, $discipline, $dateText, $tournamentType);
            $detail['challonge_id'] = $challonge['id'];
            $detail['challonge_slug'] = $challonge['slug'];
            $detail['challonge_url'] = $challonge['url'];
        } catch (Throwable $e) {
            $detail['challonge_error'] = $e->getMessage();
        }
        $stmt = $pdo->prepare('INSERT INTO tournaments
              (id, title, href, source_kind, status_class, date_text, club, participants_count, participants_limit, source_page, comp_id, detail_json, detail_fetched_at, created_at, updated_at)
              VALUES (:id, :title, :href, "next", "future", :date_text, :club, 0, :participants_limit, NULL, NULL, :detail_json, :detail_fetched_at, :created_at, :updated_at)');
        $stmt->execute([
            ':id' => $nextId,
            ':title' => $title,
            ':href' => '/t/' . $nextId,
            ':date_text' => $dateText,
            ':club' => $club,
            ':participants_limit' => $capacity > 0 ? $capacity : null,
            ':detail_json' => json_encode($detail, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            ':detail_fetched_at' => $now,
            ':created_at' => $now,
            ':updated_at' => $now,
        ]);
        $stmt = $pdo->prepare('SELECT * FROM tournaments WHERE id = ?');
        $stmt->execute([$nextId]);
        respond(['ok' => true, 'item' => tournament_response_row($stmt->fetch() ?: [])], 201);
    }

    if ($resource === 'tournament_registration') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_app_tournament_participants_table($pdo);
        $body = json_body();
        $tournamentId = (int)($body['tournament_id'] ?? 0);
        $action = (string)($body['action'] ?? 'register');
        $playerId = (int)($body['player_id'] ?? 0);
        $username = trim((string)($body['username'] ?? ''));
        $name = trim((string)($body['name'] ?? $username));
        $city = trim((string)($body['city'] ?? ''));
        if ($tournamentId <= 0 || !in_array($action, ['register', 'unregister'], true)) {
            respond(['error' => 'bad_request'], 400);
        }
        if ($playerId <= 0 && $username === '') {
            respond(['error' => 'player_required'], 400);
        }
        if ($name === '') {
            $name = $username !== '' ? $username : 'Игрок ' . $playerId;
        }
        if (mb_strlen($name) > 255 || mb_strlen($city) > 255 || mb_strlen($username) > 190) {
            respond(['error' => 'value_too_long'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM tournaments WHERE id = ?');
        $stmt->execute([$tournamentId]);
        $tournament = $stmt->fetch();
        if (!$tournament) {
            respond(['error' => 'tournament_not_found'], 404);
        }
        if (!is_app_created_tournament($tournament)) {
            respond(['error' => 'not_app_created_tournament'], 409);
        }

        $lookupSql = $playerId > 0
            ? 'SELECT * FROM app_tournament_participants WHERE tournament_id = :tournament_id AND player_id = :player_id LIMIT 1'
            : 'SELECT * FROM app_tournament_participants WHERE tournament_id = :tournament_id AND registered_by = :username LIMIT 1';
        $stmt = $pdo->prepare($lookupSql);
        $stmt->bindValue(':tournament_id', $tournamentId, PDO::PARAM_INT);
        if ($playerId > 0) {
            $stmt->bindValue(':player_id', $playerId, PDO::PARAM_INT);
        } else {
            $stmt->bindValue(':username', $username, PDO::PARAM_STR);
        }
        $stmt->execute();
        $existing = $stmt->fetch();

        if ($action === 'unregister') {
            if ($existing && (int)($existing['active'] ?? 0) === 1) {
                $challongeParticipantId = (int)($existing['challonge_participant_id'] ?? 0);
                if ($challongeParticipantId > 0) {
                    challonge_delete_participant($config, $tournament, $challongeParticipantId);
                }
                $stmt = $pdo->prepare('UPDATE app_tournament_participants
                                       SET active = 0, updated_at = NOW()
                                       WHERE id = :id');
                $stmt->execute([':id' => (int)$existing['id']]);
            }
            $participants = app_tournament_participants($pdo, $tournamentId);
            $stmt = $pdo->prepare('UPDATE tournaments SET participants_count = :count, updated_at = NOW() WHERE id = :id');
            $stmt->execute([':count' => count($participants), ':id' => $tournamentId]);
            respond([
                'ok' => true,
                'state' => 'not_registered',
                'message' => 'Запись отменена.',
                'participants_count' => count($participants),
                'participants' => $participants,
            ]);
        }

        if ($existing && (int)($existing['active'] ?? 0) === 1) {
            $participants = app_tournament_participants($pdo, $tournamentId);
            respond([
                'ok' => true,
                'state' => 'registered',
                'message' => 'Вы уже записаны на этот турнир.',
                'participants_count' => count($participants),
                'participants' => $participants,
            ]);
        }

        $participant = challonge_create_participant($config, $tournament, $name, $playerId > 0 ? $playerId : null);
        $challongeParticipantId = (int)($participant['id'] ?? 0);
        if ($existing) {
            $stmt = $pdo->prepare('UPDATE app_tournament_participants
                                   SET player_id = :player_id, name = :name, city = :city,
                                       challonge_participant_id = :challonge_participant_id,
                                       registered_by = :registered_by, request_ip = :request_ip,
                                       active = 1, updated_at = NOW()
                                   WHERE id = :id');
            $stmt->execute([
                ':player_id' => $playerId > 0 ? $playerId : null,
                ':name' => $name,
                ':city' => $city,
                ':challonge_participant_id' => $challongeParticipantId > 0 ? $challongeParticipantId : null,
                ':registered_by' => $username,
                ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? '',
                ':id' => (int)$existing['id'],
            ]);
        } else {
            $stmt = $pdo->prepare('INSERT INTO app_tournament_participants
                  (tournament_id, player_id, name, city, challonge_participant_id, registered_by, request_ip, active)
                  VALUES (:tournament_id, :player_id, :name, :city, :challonge_participant_id, :registered_by, :request_ip, 1)');
            $stmt->execute([
                ':tournament_id' => $tournamentId,
                ':player_id' => $playerId > 0 ? $playerId : null,
                ':name' => $name,
                ':city' => $city,
                ':challonge_participant_id' => $challongeParticipantId > 0 ? $challongeParticipantId : null,
                ':registered_by' => $username,
                ':request_ip' => $_SERVER['REMOTE_ADDR'] ?? '',
            ]);
        }

        $participants = app_tournament_participants($pdo, $tournamentId);
        $stmt = $pdo->prepare('UPDATE tournaments SET participants_count = :count, updated_at = NOW() WHERE id = :id');
        $stmt->execute([':count' => count($participants), ':id' => $tournamentId]);
        respond([
            'ok' => true,
            'state' => 'registered',
            'message' => 'Вы записаны на турнир.',
            'participants_count' => count($participants),
            'participants' => $participants,
        ]);
    }

    if ($resource === 'active_match') {
        ensure_app_tournament_participants_table($pdo);
        $tournamentId = (int)($_GET['tournament_id'] ?? 0);
        $playerId = (int)($_GET['player_id'] ?? 0);
        if ($tournamentId <= 0 || $playerId <= 0) {
            respond(['error' => 'tournament_and_player_required'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM tournaments WHERE id = ?');
        $stmt->execute([$tournamentId]);
        $tournament = $stmt->fetch();
        if (!$tournament) {
            respond(['error' => 'tournament_not_found'], 404);
        }
        if (!is_app_created_tournament($tournament)) {
            respond(['error' => 'not_app_created_tournament'], 409);
        }
        $stmt = $pdo->prepare('SELECT * FROM app_tournament_participants
                               WHERE tournament_id = :tournament_id AND player_id = :player_id AND active = 1
                               LIMIT 1');
        $stmt->execute([':tournament_id' => $tournamentId, ':player_id' => $playerId]);
        $participant = $stmt->fetch();
        if (!$participant) {
            respond(['ok' => true, 'item' => null, 'message' => 'Вы не записаны на этот турнир.']);
        }
        $myParticipantId = (int)($participant['challonge_participant_id'] ?? 0);
        if ($myParticipantId <= 0) {
            respond(['ok' => true, 'item' => null, 'message' => 'Участник еще не связан с сеткой Challonge.']);
        }
        $matches = challonge_matches($config, $tournament);
        $active = null;
        foreach ($matches as $row) {
            $match = $row['match'] ?? $row;
            if (!is_array($match)) {
                continue;
            }
            $state = strtolower((string)($match['state'] ?? ''));
            $player1Id = (int)($match['player1_id'] ?? 0);
            $player2Id = (int)($match['player2_id'] ?? 0);
            if (($player1Id === $myParticipantId || $player2Id === $myParticipantId) && !in_array($state, ['complete', 'completed'], true)) {
                $active = challonge_match_response($match, $myParticipantId, (string)($participant['name'] ?? ''));
                break;
            }
        }
        respond(['ok' => true, 'item' => $active]);
    }

    if ($resource === 'match_score') {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            respond(['error' => 'method_not_allowed'], 405);
        }
        ensure_app_tournament_participants_table($pdo);
        $body = json_body();
        $tournamentId = (int)($body['tournament_id'] ?? 0);
        $playerId = (int)($body['player_id'] ?? 0);
        $matchId = (int)($body['match_id'] ?? 0);
        $myScore = (int)($body['my_score'] ?? -1);
        $opponentScore = (int)($body['opponent_score'] ?? -1);
        if ($tournamentId <= 0 || $playerId <= 0 || $matchId <= 0 || $myScore < 0 || $opponentScore < 0) {
            respond(['error' => 'bad_request'], 400);
        }
        if ($myScore === $opponentScore) {
            respond(['error' => 'winner_required'], 400);
        }
        $stmt = $pdo->prepare('SELECT * FROM tournaments WHERE id = ?');
        $stmt->execute([$tournamentId]);
        $tournament = $stmt->fetch();
        if (!$tournament) {
            respond(['error' => 'tournament_not_found'], 404);
        }
        if (!is_app_created_tournament($tournament)) {
            respond(['error' => 'not_app_created_tournament'], 409);
        }
        $stmt = $pdo->prepare('SELECT * FROM app_tournament_participants
                               WHERE tournament_id = :tournament_id AND player_id = :player_id AND active = 1
                               LIMIT 1');
        $stmt->execute([':tournament_id' => $tournamentId, ':player_id' => $playerId]);
        $participant = $stmt->fetch();
        if (!$participant) {
            respond(['error' => 'participant_not_registered'], 409);
        }
        $myParticipantId = (int)($participant['challonge_participant_id'] ?? 0);
        $matches = challonge_matches($config, $tournament);
        $target = null;
        foreach ($matches as $row) {
            $match = $row['match'] ?? $row;
            if (is_array($match) && (int)($match['id'] ?? 0) === $matchId) {
                $target = $match;
                break;
            }
        }
        if (!$target) {
            respond(['error' => 'match_not_found'], 404);
        }
        $player1Id = (int)($target['player1_id'] ?? 0);
        $player2Id = (int)($target['player2_id'] ?? 0);
        if ($player1Id !== $myParticipantId && $player2Id !== $myParticipantId) {
            respond(['error' => 'match_not_owned_by_player'], 403);
        }
        $mySlot = $player1Id === $myParticipantId ? 1 : 2;
        $score1 = $mySlot === 1 ? $myScore : $opponentScore;
        $score2 = $mySlot === 1 ? $opponentScore : $myScore;
        $winnerId = $score1 > $score2 ? $player1Id : $player2Id;
        $updated = challonge_update_match_score($config, $tournament, $matchId, $score1 . '-' . $score2, $winnerId);
        respond([
            'ok' => true,
            'item' => challonge_match_response($updated, $myParticipantId, (string)($participant['name'] ?? '')),
            'message' => 'Счет отправлен в Challonge.',
        ]);
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
            $where[] = '(p.name LIKE :q OR p.id = :q_id)';
            $params[':q'] = '%' . $playerQuery . '%';
            $params[':q_id'] = ctype_digit($playerQuery) ? (int)$playerQuery : 0;
        }
        $city = trim((string)($_GET['city'] ?? ''));
        if ($city !== '') {
            $where[] = 'p.city = :city';
            $params[':city'] = $city;
        }
        $ratingNeedles = [
            'russian_billiards' => [
                'rating_key' => ['%pyramid%', '%russian%'],
                'text' => ['%пирамид%', '%русск%'],
            ],
            'pool' => [
                'rating_key' => ['%pool%'],
                'text' => ['%пул%', '%pool%'],
            ],
            'snooker' => [
                'rating_key' => ['%snooker%'],
                'text' => ['%снукер%', '%snooker%'],
            ],
        ];
        $discipline = trim((string)($_GET['discipline'] ?? ''));
        $disciplineSql = '';
        if (isset($ratingNeedles[$discipline])) {
            $parts = [];
            foreach ($ratingNeedles[$discipline]['rating_key'] as $i => $needle) {
                $key = ':discipline_key_' . $i;
                $parts[] = 'fr.rating_key LIKE ' . $key;
                $params[$key] = $needle;
            }
            foreach ($ratingNeedles[$discipline]['text'] as $i => $needle) {
                $key = ':discipline_text_' . $i;
                $parts[] = 'fr.discipline LIKE ' . $key . ' OR fr.rating_label LIKE ' . $key;
                $params[$key] = $needle;
            }
            $disciplineSql = '(' . implode(' OR ', $parts) . ')';
            $where[] = 'EXISTS (SELECT 1 FROM player_ratings fr WHERE fr.player_id = p.id AND ' . $disciplineSql . ')';
        }
        $rbEloSql = "MAX(CASE WHEN r.rating_key LIKE '%pyramid%' OR r.rating_key LIKE '%russian%' OR r.discipline LIKE '%пирамид%' OR r.rating_label LIKE '%пирамид%' OR r.rating_label LIKE '%русск%' THEN r.elo END)";
        $poolEloSql = "MAX(CASE WHEN r.rating_key LIKE '%pool%' OR r.discipline LIKE '%пул%' OR r.discipline LIKE '%pool%' OR r.rating_label LIKE '%пул%' OR r.rating_label LIKE '%pool%' THEN r.elo END)";
        $snookerEloSql = "MAX(CASE WHEN r.rating_key LIKE '%snooker%' OR r.discipline LIKE '%снукер%' OR r.discipline LIKE '%snooker%' OR r.rating_label LIKE '%снукер%' OR r.rating_label LIKE '%snooker%' THEN r.elo END)";
        $statsTextSql = "JSON_UNQUOTE(JSON_EXTRACT(p.detail_json, '$.\"_sections\".\"Статистика\"'))";
        $tournamentsCountSql = "CAST(REGEXP_REPLACE(REGEXP_SUBSTR($statsTextSql, 'Турниров[[:space:]]*:[[:space:]]*[0-9]+'), '[^0-9]', '') AS UNSIGNED)";
        if (!empty($_GET['rating_key'])) {
            $where[] = 'r.rating_key = :rating_key';
            $params[':rating_key'] = $_GET['rating_key'];
        }
        $sql = 'SELECT p.id, p.name, p.city, p.country, p.avatar_url, p.elo, p.detail_fetched_at,
                       p.contacts_raw, p.phone, p.email, p.telegram, p.whatsapp,
                       ' . $rbEloSql . ' AS rb_elo,
                       ' . $poolEloSql . ' AS pool_elo,
                       ' . $snookerEloSql . ' AS snooker_elo,
                       MAX(r.elo) AS best_elo,
                       COALESCE(' . $tournamentsCountSql . ', 0) AS tournaments_count,
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
        $sort = trim((string)($_GET['sort'] ?? 'best_elo'));
        $direction = strtolower(trim((string)($_GET['direction'] ?? 'desc'))) === 'asc' ? 'ASC' : 'DESC';
        $having = [];
        $orderSql = match ($sort) {
            'surname', 'name' => 'p.name ' . $direction,
            'rb_elo', 'russian_billiards' => 'rb_elo ' . $direction . ', p.name ASC',
            'pool_elo', 'pool' => 'pool_elo ' . $direction . ', p.name ASC',
            'snooker_elo', 'snooker' => 'snooker_elo ' . $direction . ', p.name ASC',
            'tournaments', 'tournaments_count' => 'tournaments_count ' . $direction . ', p.name ASC',
            default => 'COALESCE(best_elo, p.elo, 0) ' . $direction . ', p.name ASC',
        };
        if (in_array($sort, ['rb_elo', 'russian_billiards'], true)) {
            $having[] = 'rb_elo IS NOT NULL';
        } elseif (in_array($sort, ['pool_elo', 'pool'], true)) {
            $having[] = 'pool_elo IS NOT NULL';
        } elseif (in_array($sort, ['snooker_elo', 'snooker'], true)) {
            $having[] = 'snooker_elo IS NOT NULL';
        } elseif (in_array($sort, ['tournaments', 'tournaments_count'], true)) {
            $having[] = 'tournaments_count > 0';
        }
        $sql .= ' GROUP BY p.id';
        if ($having) {
            $sql .= ' HAVING ' . implode(' AND ', $having);
        }
        $sql .= ' ORDER BY ' . $orderSql . ' LIMIT :limit OFFSET :offset';
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
                                      t.participants_count, t.participants_limit, t.comp_id, t.detail_json, t.detail_fetched_at,
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
        $storedParticipantsCount = (int)($tournament['participants_count'] ?? 0);

        $participants = [];
        $isAppCreatedTournament = is_app_created_tournament($tournament);
        $isFutureTournament = ($tournament['source_kind'] ?? '') === 'next' || ($tournament['status_class'] ?? '') === 'future';
        $registeredParticipants = [];
        if ($isAppCreatedTournament) {
            $participants = app_tournament_participants($pdo, (int)$tournament['id']);
            $tournament['participants_count'] = count($participants);
        } elseif ($isFutureTournament) {
            $registeredParticipants = parse_registered_participants((int)$tournament['id']);
        }

        if ($isAppCreatedTournament) {
            // App-created tournaments are owned by this backend; never scrape LLB for them.
        } elseif ($isFutureTournament) {
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
        if ((int)$tournament['participants_count'] !== $storedParticipantsCount) {
            $stmt = $pdo->prepare('UPDATE tournaments
                                   SET participants_count = :participants_count,
                                       detail_fetched_at = NOW(),
                                       updated_at = NOW()
                                   WHERE id = :id');
            $stmt->execute([
                ':participants_count' => (int)$tournament['participants_count'],
                ':id' => (int)$tournament['id'],
            ]);
        }

        $detail = tournament_detail_data($tournament);
        $tournament['city'] = (string)($detail['city'] ?? '');
        $tournament['discipline'] = (string)($detail['discipline'] ?? '');
        $tournament['app_created'] = is_app_created_tournament($tournament);
        $tournament['bracket_url'] = tournament_link_url($tournament);

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
        ensure_tournament_media_table($pdo);
        $stmt = $pdo->prepare('SELECT * FROM tournament_media
                               WHERE tournament_id = :id
                               ORDER BY id DESC
                               LIMIT 100');
        $stmt->execute([':id' => $id]);
        $tournament['media'] = array_map('media_response_row', $stmt->fetchAll());
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
            $where[] = 'LOWER(t.date_text) NOT LIKE "%отмен%"';
            $where[] = '(COALESCE(
                STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%y"),
                STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%Y")
            ) >= CURDATE() OR (
                JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.created_by_app")) = "true" AND COALESCE(
                    STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%y"),
                    STR_TO_DATE(SUBSTRING_INDEX(REPLACE(t.date_text, "\n", " "), " ", 1), "%d.%m.%Y")
                ) IS NULL
            ))';
            $params[':source_kind'] = 'next';
            $params[':status_class'] = 'future';
        } elseif (in_array($status, ['online', 'live', 'current', 'running'], true)) {
            $where[] = '(t.source_kind = :source_kind OR t.status_class IN ("running", "live"))';
            $params[':source_kind'] = 'online';
        }

        $sql = 'SELECT t.id, t.title, t.source_kind, t.status_class, t.date_text,
                                      JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.city")) AS city,
                                      t.club,
                                      JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.discipline")) AS discipline,
                                      JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.created_by_app")) = "true" AS app_created,
                                      t.participants_count, t.participants_limit, t.comp_id, t.detail_json, t.detail_fetched_at,
                                      CASE
                                        WHEN t.source_kind = "next" OR t.status_class = "future" THEN 0
                                        ELSE COUNT(m.game_no)
                                      END AS matches_count,
                                      CASE
                                        WHEN JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.challonge_url")) IS NOT NULL AND JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.challonge_url")) != "" THEN JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.challonge_url"))
                                        WHEN JSON_UNQUOTE(JSON_EXTRACT(t.detail_json, "$.created_by_app")) = "true" THEN CONCAT("https://llb.panfilius.ru/flutter_app/#/tournaments/", t.id)
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
