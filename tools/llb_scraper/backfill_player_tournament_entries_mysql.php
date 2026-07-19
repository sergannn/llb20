<?php
/**
 * Backfill player_tournament_entries from already imported tournament data.
 *
 * Run on the server after importing tournament_participants/matches:
 *   php tools/llb_scraper/backfill_player_tournament_entries_mysql.php
 *
 * By default it reads the production API config. Override with:
 *   LLB_API_CONFIG=/path/to/llb_api_config.php php ...
 */

$configPath = getenv('LLB_API_CONFIG') ?: '/var/www/www-root/data/www/llb.panfilius.ru/llb_api_config.php';
if (!is_file($configPath)) {
    fwrite(STDERR, "Config not found: {$configPath}\n");
    exit(1);
}

$config = require $configPath;
$pdo = new PDO(
    "mysql:host={$config['host']};port={$config['port']};dbname={$config['database']};charset=utf8mb4",
    $config['user'],
    $config['password'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$now = gmdate('c');
$beforeRows = (int)$pdo->query('SELECT COUNT(*) FROM player_tournament_entries')->fetchColumn();
$beforePlayers = (int)$pdo->query('SELECT COUNT(DISTINCT player_id) FROM player_tournament_entries')->fetchColumn();

$pdo->beginTransaction();

$participantsSql = <<<'SQL'
INSERT INTO player_tournament_entries (
    player_id, membership_node_id, tournament_id, title, date_text,
    points, place, source_page, fetched_at
)
SELECT tp.player_id,
       0 AS membership_node_id,
       t.id AS tournament_id,
       t.title,
       t.date_text,
       NULL AS points,
       NULLIF(MIN(CAST(tp.place AS CHAR)), '') AS place,
       -2 AS source_page,
       :now AS fetched_at
FROM tournament_participants tp
JOIN tournaments t ON t.comp_id = tp.comp_id
WHERE tp.player_id IS NOT NULL
  AND tp.player_id > 0
  AND NOT EXISTS (
      SELECT 1 FROM player_tournament_entries e
      WHERE e.player_id = tp.player_id AND e.tournament_id = t.id
  )
GROUP BY tp.player_id, t.id, t.title, t.date_text
SQL;
$stmt = $pdo->prepare($participantsSql);
$stmt->execute([':now' => $now]);
$participantsInserted = $stmt->rowCount();

$matchesSql = <<<'SQL'
INSERT INTO player_tournament_entries (
    player_id, membership_node_id, tournament_id, title, date_text,
    points, place, source_page, fetched_at
)
SELECT x.player_id,
       0 AS membership_node_id,
       t.id AS tournament_id,
       t.title,
       t.date_text,
       NULL AS points,
       NULL AS place,
       -3 AS source_page,
       :now AS fetched_at
FROM (
    SELECT tournament_id, player1_id AS player_id
    FROM matches
    WHERE player1_id IS NOT NULL AND player1_id > 0 AND tournament_id IS NOT NULL
    UNION
    SELECT tournament_id, player2_id AS player_id
    FROM matches
    WHERE player2_id IS NOT NULL AND player2_id > 0 AND tournament_id IS NOT NULL
) x
JOIN tournaments t ON t.id = x.tournament_id
WHERE NOT EXISTS (
    SELECT 1 FROM player_tournament_entries e
    WHERE e.player_id = x.player_id AND e.tournament_id = t.id
)
GROUP BY x.player_id, t.id, t.title, t.date_text
SQL;
$stmt = $pdo->prepare($matchesSql);
$stmt->execute([':now' => $now]);
$matchesInserted = $stmt->rowCount();

$pdo->commit();

$afterRows = (int)$pdo->query('SELECT COUNT(*) FROM player_tournament_entries')->fetchColumn();
$afterPlayers = (int)$pdo->query('SELECT COUNT(DISTINCT player_id) FROM player_tournament_entries')->fetchColumn();
$missingParticipantPlayers = (int)$pdo
    ->query('SELECT COUNT(DISTINCT tp.player_id)
             FROM tournament_participants tp
             WHERE tp.player_id > 0
               AND NOT EXISTS (
                   SELECT 1 FROM player_tournament_entries e
                   WHERE e.player_id = tp.player_id
               )')
    ->fetchColumn();

echo "before_rows={$beforeRows} before_players={$beforePlayers}\n";
echo "participants_inserted={$participantsInserted} matches_inserted={$matchesInserted}\n";
echo "after_rows={$afterRows} after_players={$afterPlayers}\n";
echo "participants_players_without_entries={$missingParticipantPlayers}\n";
