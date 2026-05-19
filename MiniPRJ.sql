

DROP DATABASE IF EXISTS mini_social_network;
CREATE DATABASE mini_social_network
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE mini_social_network;

CREATE TABLE users (
    user_id    INT          NOT NULL AUTO_INCREMENT,
    username   VARCHAR(50)  NOT NULL,
    password   VARCHAR(255) NOT NULL,          -- Đã mã hóa (hashed)
    email      VARCHAR(100) NOT NULL,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_username (username),
    UNIQUE KEY uq_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE posts (
    post_id       INT  NOT NULL AUTO_INCREMENT,
    user_id       INT  NOT NULL,
    content       TEXT NOT NULL,
    like_count    INT  NOT NULL DEFAULT 0,   
    comment_count INT  NOT NULL DEFAULT 0,  
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id),
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT          
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE posts ADD FULLTEXT INDEX ft_posts_content (content);


-- ------------------------------------------------------------
-- 3.3 Bảng comments (Bình luận)
-- ------------------------------------------------------------
CREATE TABLE comments (
    comment_id INT  NOT NULL AUTO_INCREMENT,
    post_id    INT  NOT NULL,
    user_id    INT  NOT NULL,
    content    TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id),
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id)
        REFERENCES posts(post_id)
        ON DELETE CASCADE,          -- Xóa post → xóa comments (3.6)
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE friends (
    friendship_id INT         NOT NULL AUTO_INCREMENT,
    user_id       INT         NOT NULL,   
    friend_id     INT         NOT NULL,    
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (friendship_id),
    UNIQUE KEY uq_friendship (
        (LEAST(user_id, friend_id)),
        (GREATEST(user_id, friend_id))
    ),
    -- Chặn tự kết bạn với chính mình
    CONSTRAINT chk_no_self_friend CHECK (user_id <> friend_id),
    -- Chặn status không hợp lệ
    CONSTRAINT chk_friend_status  CHECK (status IN ('pending', 'accepted')),
    CONSTRAINT fk_friends_user   FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id)
        REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ------------------------------------------------------------
-- 3.5 Bảng likes (Lượt thích)
-- ------------------------------------------------------------
CREATE TABLE likes (
    like_id    INT NOT NULL AUTO_INCREMENT,
    user_id    INT NOT NULL,
    post_id    INT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (like_id),
    UNIQUE KEY uq_like (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id)
        REFERENCES posts(post_id)
        ON DELETE CASCADE        
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE post_logs (
    log_id     INT          NOT NULL AUTO_INCREMENT,
    post_id    INT          NOT NULL,
    user_id    INT          NOT NULL,
    content    TEXT         NOT NULL,
    deleted_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



DELIMITER $$

CREATE TRIGGER trg_likes_after_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    like_count = like_count + 1
    WHERE  post_id = NEW.post_id;
END$$

CREATE TRIGGER trg_likes_after_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    like_count = like_count - 1
    WHERE  post_id = OLD.post_id;
END$$

-- ------------------------------------------------------------
-- 4.1: Trigger tăng comment_count khi INSERT vào comments
-- ------------------------------------------------------------
CREATE TRIGGER trg_comments_after_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    comment_count = comment_count + 1
    WHERE  post_id = NEW.post_id;
END$$

-- ------------------------------------------------------------
-- 4.1: Trigger giảm comment_count khi DELETE khỏi comments
-- ------------------------------------------------------------
CREATE TRIGGER trg_comments_after_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    comment_count = comment_count - 1
    WHERE  post_id = OLD.post_id;
END$$

-- ------------------------------------------------------------
-- 4.1 (Tùy chọn): Trigger ghi log khi xóa bài viết
-- ------------------------------------------------------------
CREATE TRIGGER trg_posts_before_delete
BEFORE DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, user_id, content, deleted_at)
    VALUES (OLD.post_id, OLD.user_id, OLD.content, NOW());
END$$

DELIMITER ;


-- ============================================================
-- SECTION 3: STORED PROCEDURES
-- ============================================================

DELIMITER $$

-- ------------------------------------------------------------
-- F01: Đăng ký thành viên
-- Tham số: p_username, p_password (đã hash ở tầng ứng dụng), p_email
-- ------------------------------------------------------------
CREATE PROCEDURE sp_register_user (
    IN  p_username VARCHAR(50),
    IN  p_password VARCHAR(255),
    IN  p_email    VARCHAR(100),
    OUT p_result   VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Username hoặc email đã tồn tại.';
    END;

    INSERT INTO users (username, password, email)
    VALUES (p_username, p_password, p_email);

    SET p_result = CONCAT('OK: Đăng ký thành công, user_id = ', LAST_INSERT_ID());
END$$


-- ------------------------------------------------------------
-- F02: Đăng bài viết
-- ------------------------------------------------------------
CREATE PROCEDURE sp_create_post (
    IN  p_user_id INT,
    IN  p_content TEXT,
    OUT p_result  VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Không thể đăng bài viết.';
    END;

    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        SET p_result = 'ERROR: Nội dung bài viết không được để trống.';
    ELSE
        INSERT INTO posts (user_id, content)
        VALUES (p_user_id, p_content);
        SET p_result = CONCAT('OK: Đăng bài thành công, post_id = ', LAST_INSERT_ID());
    END IF;
END$$


-- ------------------------------------------------------------
-- F04: Gửi lời mời kết bạn
-- Sử dụng Constraints + kiểm tra thêm qua SP
-- ------------------------------------------------------------
CREATE PROCEDURE sp_send_friend_request (
    IN  p_user_id   INT,
    IN  p_friend_id INT,
    OUT p_result    VARCHAR(200)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Không thể gửi lời mời (đã tồn tại hoặc lỗi hệ thống).';
    END;

    -- Kiểm tra không tự kết bạn
    IF p_user_id = p_friend_id THEN
        SET p_result = 'ERROR: Không thể tự kết bạn với chính mình.';
        LEAVE sp_send_friend_request;  -- label không dùng được trong SP đơn giản, dùng IF/ELSE
    END IF;

    -- Kiểm tra đã có quan hệ chưa (cả 2 chiều)
    SELECT COUNT(*) INTO v_exists
    FROM   friends
    WHERE  LEAST(user_id, friend_id)    = LEAST(p_user_id, p_friend_id)
      AND  GREATEST(user_id, friend_id) = GREATEST(p_user_id, p_friend_id);

    IF v_exists > 0 THEN
        SET p_result = 'ERROR: Lời mời kết bạn hoặc quan hệ bạn bè đã tồn tại.';
    ELSE
        INSERT INTO friends (user_id, friend_id, status)
        VALUES (p_user_id, p_friend_id, 'pending');
        SET p_result = CONCAT('OK: Đã gửi lời mời kết bạn, friendship_id = ', LAST_INSERT_ID());
    END IF;
END$$


-- ------------------------------------------------------------
-- F05: Chấp nhận lời mời kết bạn (dùng Transaction – mục 4.2)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_accept_friend_request (
    IN  p_friendship_id INT,
    IN  p_friend_id     INT,   -- người nhận (để kiểm tra quyền)
    OUT p_result        VARCHAR(200)
)
BEGIN
    DECLARE v_status  VARCHAR(20) DEFAULT '';
    DECLARE v_recv_id INT         DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR: Không thể chấp nhận lời mời.';
    END;

    START TRANSACTION;

    SELECT status, friend_id
    INTO   v_status, v_recv_id
    FROM   friends
    WHERE  friendship_id = p_friendship_id
    FOR UPDATE;

    IF v_recv_id <> p_friend_id THEN
        ROLLBACK;
        SET p_result = 'ERROR: Bạn không có quyền chấp nhận lời mời này.';
    ELSEIF v_status <> 'pending' THEN
        ROLLBACK;
        SET p_result = 'ERROR: Lời mời không ở trạng thái pending.';
    ELSE
        UPDATE friends
        SET    status = 'accepted'
        WHERE  friendship_id = p_friendship_id;

        COMMIT;
        SET p_result = 'OK: Đã chấp nhận lời mời kết bạn.';
    END IF;
END$$


-- ------------------------------------------------------------
-- F05: Hủy / từ chối lời mời kết bạn
-- ------------------------------------------------------------
CREATE PROCEDURE sp_cancel_friend_request (
    IN  p_friendship_id INT,
    IN  p_user_id       INT,   -- người gửi hoặc người nhận đều có thể hủy
    OUT p_result        VARCHAR(200)
)
BEGIN
    DECLARE v_count INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Không thể hủy lời mời.';
    END;

    SELECT COUNT(*) INTO v_count
    FROM   friends
    WHERE  friendship_id = p_friendship_id
      AND  (user_id = p_user_id OR friend_id = p_user_id);

    IF v_count = 0 THEN
        SET p_result = 'ERROR: Không tìm thấy lời mời hoặc không có quyền.';
    ELSE
        DELETE FROM friends WHERE friendship_id = p_friendship_id;
        SET p_result = 'OK: Đã hủy lời mời / quan hệ kết bạn.';
    END IF;
END$$


-- ------------------------------------------------------------
-- F08: Báo cáo hoạt động của user
-- ------------------------------------------------------------
CREATE PROCEDURE sp_user_activity_report (
    IN p_user_id INT
)
BEGIN
    SELECT
        u.user_id,
        u.username,
        u.email,
        u.created_at                              AS joined_at,
        COUNT(DISTINCT p.post_id)                 AS total_posts,
        COALESCE(SUM(p.like_count), 0)            AS total_likes_received,
        COALESCE(SUM(p.comment_count), 0)         AS total_comments_received
    FROM  users u
    LEFT JOIN posts p ON p.user_id = u.user_id
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id, u.username, u.email, u.created_at;
END$$


-- ------------------------------------------------------------
-- F09: Gợi ý kết bạn (Bạn của bạn – dùng CTE, MySQL 8+)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_friend_suggestions (
    IN  p_user_id INT,
    IN  p_limit   INT
)
BEGIN
    -- Lấy danh sách bạn bè hiện tại (accepted, 2 chiều)
    WITH current_friends AS (
        SELECT friend_id AS fid
        FROM   friends
        WHERE  user_id = p_user_id AND status = 'accepted'
        UNION
        SELECT user_id AS fid
        FROM   friends
        WHERE  friend_id = p_user_id AND status = 'accepted'
    ),
    -- Lấy bạn của bạn
    friends_of_friends AS (
        SELECT
            CASE
                WHEN f.user_id   IN (SELECT fid FROM current_friends) THEN f.friend_id
                ELSE f.user_id
            END AS suggested_id,
            COUNT(*) AS mutual_count
        FROM  friends f
        WHERE (f.user_id   IN (SELECT fid FROM current_friends)
            OR f.friend_id IN (SELECT fid FROM current_friends))
          AND f.status = 'accepted'
        GROUP BY suggested_id
    )
    SELECT
        u.user_id,
        u.username,
        u.email,
        fof.mutual_count AS so_ban_chung
    FROM  friends_of_friends fof
    JOIN  users u ON u.user_id = fof.suggested_id
    WHERE fof.suggested_id <> p_user_id
      AND fof.suggested_id NOT IN (SELECT fid FROM current_friends)
    ORDER BY fof.mutual_count DESC
    LIMIT p_limit;
END$$


-- ------------------------------------------------------------
-- F10: Xóa bài viết (Transaction – likes & comments xóa qua CASCADE)
-- ------------------------------------------------------------
CREATE PROCEDURE sp_delete_post (
    IN  p_post_id INT,
    IN  p_user_id INT,   -- chỉ chủ bài viết mới được xóa
    OUT p_result  VARCHAR(200)
)
BEGIN
    DECLARE v_owner INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR: Xóa bài viết thất bại, đã rollback.';
    END;

    START TRANSACTION;

    SELECT user_id INTO v_owner
    FROM   posts
    WHERE  post_id = p_post_id
    FOR UPDATE;

    IF v_owner <> p_user_id THEN
        ROLLBACK;
        SET p_result = 'ERROR: Bạn không có quyền xóa bài viết này.';
    ELSE
        -- likes & comments xóa tự động qua ON DELETE CASCADE
        DELETE FROM posts WHERE post_id = p_post_id;
        COMMIT;
        SET p_result = 'OK: Đã xóa bài viết và dữ liệu liên quan.';
    END IF;
END$$


-- ------------------------------------------------------------
-- F11: Xóa tài khoản người dùng (Transaction – All or Nothing)
-- Thứ tự: likes → comments → friends → posts → users
-- ------------------------------------------------------------
CREATE PROCEDURE sp_delete_user (
    IN  p_user_id INT,
    OUT p_result  VARCHAR(200)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR: Xóa tài khoản thất bại, toàn bộ đã được rollback.';
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists FROM users WHERE user_id = p_user_id;

    IF v_exists = 0 THEN
        ROLLBACK;
        SET p_result = 'ERROR: Tài khoản không tồn tại.';
    ELSE
        -- Bước 1: Xóa likes của user
        DELETE FROM likes    WHERE user_id = p_user_id;

        -- Bước 2: Xóa comments của user
        DELETE FROM comments WHERE user_id = p_user_id;

        -- Bước 3: Xóa các quan hệ bạn bè (2 chiều)
        DELETE FROM friends  WHERE user_id = p_user_id OR friend_id = p_user_id;

        -- Bước 4: Xóa bài viết (likes & comments của người khác trên bài này xóa qua CASCADE)
        DELETE FROM posts    WHERE user_id = p_user_id;

        -- Bước 5: Xóa tài khoản
        DELETE FROM users    WHERE user_id = p_user_id;

        COMMIT;
        SET p_result = 'OK: Đã xóa tài khoản và toàn bộ dữ liệu liên quan.';
    END IF;
END$$

DELIMITER ;


CREATE OR REPLACE VIEW vw_user_profile AS
SELECT
    u.user_id,
    u.username,
    u.email,
    u.created_at                              AS joined_at,
    COUNT(DISTINCT p.post_id)                 AS total_posts,
    COALESCE(SUM(p.like_count), 0)            AS total_likes_received,
    COALESCE(SUM(p.comment_count), 0)         AS total_comments_received,
    (
        SELECT COUNT(*)
        FROM   friends f
        WHERE  (f.user_id = u.user_id OR f.friend_id = u.user_id)
          AND  f.status = 'accepted'
    ) AS total_friends
FROM  users u
LEFT JOIN posts p ON p.user_id = u.user_id
GROUP BY u.user_id, u.username, u.email, u.created_at;


CREATE OR REPLACE VIEW vw_user_activity AS
SELECT
    u.user_id,
    u.username,
    p.post_id,
    p.content,
    p.like_count,
    p.comment_count,
    p.created_at AS post_created_at
FROM  users u
JOIN  posts p ON p.user_id = u.user_id;

CREATE INDEX idx_posts_user_id    ON posts    (user_id);
CREATE INDEX idx_comments_post_id ON comments (post_id);
CREATE INDEX idx_comments_user_id ON comments (user_id);
CREATE INDEX idx_likes_post_id    ON likes    (post_id);
CREATE INDEX idx_friends_status   ON friends  (status);


INSERT INTO users (username, password, email) VALUES
('alice',   SHA2('alice123', 256),   'alice@example.com'),
('bob',     SHA2('bob123',   256),   'bob@example.com'),
('charlie', SHA2('charlie123',256),  'charlie@example.com'),
('diana',   SHA2('diana123', 256),   'diana@example.com');

-- Posts
INSERT INTO posts (user_id, content) VALUES
(1, 'Chào mọi người! Đây là bài viết đầu tiên của Alice.'),
(1, 'Alice đăng bài lần 2 – hôm nay trời đẹp quá!'),
(2, 'Bob chia sẻ: MySQL 8 thật sự mạnh với CTE và Window Functions.'),
(3, 'Charlie: Trigger trong MySQL giúp mình tiết kiệm rất nhiều code ứng dụng.');

-- Likes
INSERT INTO likes (user_id, post_id) VALUES
(2, 1), (3, 1), (4, 1),   
(1, 3), (4, 3),           
(1, 4);                 

-- Comments
INSERT INTO comments (post_id, user_id, content) VALUES
(1, 2, 'Chào Alice! Mình là Bob.'),
(1, 3, 'Xin chào từ Charlie!'),
(3, 1, 'Mình đồng ý, CTE rất tiện!'),
(4, 2, 'Trigger tuyệt vời thật Bob à.');

-- Friend requests
INSERT INTO friends (user_id, friend_id, status) VALUES
(1, 2, 'accepted'),   -- Alice & Bob là bạn
(1, 3, 'accepted'),   -- Alice & Charlie là bạn
(2, 4, 'pending'),    -- Bob gửi lời mời cho Diana (chưa chấp nhận)
(3, 4, 'accepted');   -- Charlie & Diana là bạn


-- ============================================================
-- SECTION 7: KIỂM THỬ NHANH (QUICK TEST QUERIES)
-- ============================================================

-- Kiểm tra like_count & comment_count đã được Trigger cập nhật
SELECT post_id, content, like_count, comment_count FROM posts;

-- Xem trang cá nhân Alice (user_id = 1)
SELECT * FROM vw_user_profile WHERE user_id = 1;

-- F07: Full-Text Search
SELECT post_id, content FROM posts
WHERE MATCH(content) AGAINST ('MySQL Trigger' IN BOOLEAN MODE);

-- F09: Gợi ý kết bạn cho Diana (user_id = 4) – kỳ vọng gợi ý Alice
CALL sp_friend_suggestions(4, 5);

-- F08: Báo cáo hoạt động của Alice
CALL sp_user_activity_report(1);

-- ============================================================
-- END OF SCRIPT
-- ============================================================
