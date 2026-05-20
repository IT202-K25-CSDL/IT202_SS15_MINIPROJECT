-- ============================================================
--  MINI SOCIAL NETWORK — Full Database Script (MySQL 8.0+)
--  Đúng 100% theo SRS: snake_case, NO CASCADE, SIGNAL SQLSTATE
-- ============================================================

DROP DATABASE IF EXISTS mini_social_network;
CREATE DATABASE mini_social_network
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE mini_social_network;

-- ============================================================
-- PHẦN 1: TẠO BẢNG
-- ============================================================

-- Bảng users
CREATE TABLE users (
    user_id    INT          NOT NULL AUTO_INCREMENT,
    username   VARCHAR(50)  NOT NULL,
    password   VARCHAR(255) NOT NULL,
    email      VARCHAR(100) NOT NULL,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_username (username),
    UNIQUE KEY uq_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Bảng posts
CREATE TABLE posts (
    post_id       INT      NOT NULL AUTO_INCREMENT,
    user_id       INT      NOT NULL,
    content       TEXT     NOT NULL,
    like_count    INT      NOT NULL DEFAULT 0,
    comment_count INT      NOT NULL DEFAULT 0,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id),
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        -- KHÔNG dùng ON DELETE CASCADE theo quy chuẩn đề bài
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Full-Text Search trên content (Chức năng 4 / quy chuẩn kỹ thuật)
ALTER TABLE posts ADD FULLTEXT INDEX ft_posts_content (content);


-- Bảng comments
CREATE TABLE comments (
    comment_id INT      NOT NULL AUTO_INCREMENT,
    post_id    INT      NOT NULL,
    user_id    INT      NOT NULL,
    content    TEXT     NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id),
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id)
        REFERENCES posts(post_id),
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id)
        REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Bảng likes
-- UNIQUE(user_id, post_id): mỗi người chỉ like 1 bài 1 lần (quy chuẩn đề bài)
CREATE TABLE likes (
    like_id    INT      NOT NULL AUTO_INCREMENT,
    user_id    INT      NOT NULL,
    post_id    INT      NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (like_id),
    UNIQUE KEY uq_like (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id)
        REFERENCES users(user_id),
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id)
        REFERENCES posts(post_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Bảng friends
CREATE TABLE friends (
    friendship_id INT         NOT NULL AUTO_INCREMENT,
    user_id       INT         NOT NULL,
    friend_id     INT         NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (friendship_id),
    CONSTRAINT chk_friend_status CHECK (status IN ('pending', 'accepted')),
    CONSTRAINT fk_friends_user   FOREIGN KEY (user_id)
        REFERENCES users(user_id),
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id)
        REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Bảng post_logs (Yêu cầu mở rộng — Audit Log)
CREATE TABLE post_logs (
    log_id       INT      NOT NULL AUTO_INCREMENT,
    post_id      INT      NOT NULL,
    post_content TEXT     NOT NULL,
    deleted_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- PHẦN 2: VIEW
-- ============================================================

-- Chức năng 1: view_user_info — Khung nhìn hồ sơ
-- Chỉ lấy 4 cột an toàn, TUYỆT ĐỐI không có password
CREATE OR REPLACE VIEW view_user_info AS
SELECT
    user_id,
    username,
    email,
    created_at
FROM users;


-- ============================================================
-- PHẦN 3: TRIGGER
-- ============================================================

DELIMITER $$

-- ----------------------------------------------------------
-- Chức năng 3: Tự động đếm tương tác — LIKES
-- ----------------------------------------------------------

-- Tăng like_count khi INSERT vào likes
CREATE TRIGGER tg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    like_count = like_count + 1
    WHERE  post_id = NEW.post_id;
END$$

-- Giảm like_count khi DELETE khỏi likes (chặn xuống dưới 0)
CREATE TRIGGER tg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    like_count = GREATEST(like_count - 1, 0)
    WHERE  post_id = OLD.post_id;
END$$

-- ----------------------------------------------------------
-- Chức năng 3: Tự động đếm tương tác — COMMENTS
-- ----------------------------------------------------------

-- Tăng comment_count khi INSERT vào comments
CREATE TRIGGER tg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    comment_count = comment_count + 1
    WHERE  post_id = NEW.post_id;
END$$

-- Giảm comment_count khi DELETE khỏi comments (chặn xuống dưới 0)
CREATE TRIGGER tg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET    comment_count = GREATEST(comment_count - 1, 0)
    WHERE  post_id = OLD.post_id;
END$$

-- ----------------------------------------------------------
-- Chức năng 6: Kiểm soát kết bạn — tg_before_friend_insert
-- Dùng SIGNAL SQLSTATE để chặn 3 loại vi phạm
-- ----------------------------------------------------------
CREATE TRIGGER tg_before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    -- Vi phạm 1: Tự kết bạn với chính mình
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lỗi: Không thể tự kết bạn với chính mình.';
    END IF;

    -- Vi phạm 2 & 3: Trùng lặp hoặc đảo chiều (A→B khi đã có B→A)
    SELECT COUNT(*) INTO v_exists
    FROM   friends
    WHERE (user_id = NEW.user_id   AND friend_id = NEW.friend_id)
       OR (user_id = NEW.friend_id AND friend_id = NEW.user_id);

    IF v_exists > 0 THEN
        SIGNAL SQLSTATE '45001'
            SET MESSAGE_TEXT = 'Lỗi: Lời mời kết bạn đã tồn tại hoặc đảo chiều.';
    END IF;
END$$

-- ----------------------------------------------------------
-- Yêu cầu mở rộng: tg_after_post_delete — Audit Log
-- Khi bài viết bị xóa, sao chép vào post_logs
-- ----------------------------------------------------------
CREATE TRIGGER tg_after_post_delete
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, post_content, deleted_at)
    VALUES (OLD.post_id, OLD.content, NOW());
END$$

DELIMITER ;


-- ============================================================
-- PHẦN 4: STORED PROCEDURES
-- ============================================================

DELIMITER $$

-- ----------------------------------------------------------
-- Chức năng 2: sp_add_user — Đăng ký tài khoản
-- Kiểm tra trùng email VÀ username trước khi INSERT
-- ----------------------------------------------------------
CREATE PROCEDURE sp_add_user (
    IN  p_username VARCHAR(50),
    IN  p_password VARCHAR(255),
    IN  p_email    VARCHAR(100),
    OUT p_message  VARCHAR(200)
)
BEGIN
    DECLARE v_count_username INT DEFAULT 0;
    DECLARE v_count_email    INT DEFAULT 0;

    SELECT COUNT(*) INTO v_count_username FROM users WHERE username = p_username;
    SELECT COUNT(*) INTO v_count_email    FROM users WHERE email    = p_email;

    IF v_count_username > 0 THEN
        SET p_message = 'Lỗi: Username đã tồn tại trong hệ thống.';
    ELSEIF v_count_email > 0 THEN
        SET p_message = 'Lỗi: Email đã được đăng ký.';
    ELSE
        INSERT INTO users (username, password, email)
        VALUES (p_username, p_password, p_email);
        SET p_message = CONCAT('Thành công: Tài khoản đã được tạo, user_id = ', LAST_INSERT_ID());
    END IF;
END$$


-- ----------------------------------------------------------
-- Chức năng 4: sp_user_activity_report — Thống kê hoạt động
-- LEFT JOIN để user chưa có tương tác vẫn hiển thị giá trị 0
-- ----------------------------------------------------------
CREATE PROCEDURE sp_user_activity_report()
BEGIN
    SELECT
        u.user_id,
        u.username,
        u.email,
        COUNT(DISTINCT p.post_id)    AS total_posts,
        COUNT(DISTINCT l.like_id)    AS total_likes,
        COUNT(DISTINCT c.comment_id) AS total_comments
    FROM      users    u
    LEFT JOIN posts    p ON p.user_id = u.user_id
    LEFT JOIN likes    l ON l.user_id = u.user_id
    LEFT JOIN comments c ON c.user_id = u.user_id
    GROUP BY u.user_id, u.username, u.email
    ORDER BY u.user_id;
END$$


-- ----------------------------------------------------------
-- Chức năng 5: sp_delete_user — Xóa tài khoản toàn vẹn
-- TRANSACTION + xóa thủ công từ bảng con → bảng cha
-- TUYỆT ĐỐI không dùng ON DELETE CASCADE
-- ----------------------------------------------------------
CREATE PROCEDURE sp_delete_user (
    IN  p_user_id INT,
    OUT p_message VARCHAR(200)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'Lỗi: Xóa tài khoản thất bại. Toàn bộ giao dịch đã được ROLLBACK.';
    END;

    SELECT COUNT(*) INTO v_exists FROM users WHERE user_id = p_user_id;

    IF v_exists = 0 THEN
        SET p_message = 'Lỗi: Không tìm thấy tài khoản với user_id đã cho.';
    ELSE
        START TRANSACTION;

            -- Bước 1: Xóa bảng con xa nhất trước
            DELETE FROM likes    WHERE user_id = p_user_id;

            -- Bước 2: Xóa likes của người khác trên bài của user này
            DELETE FROM likes    WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);

            -- Bước 3: Xóa comments của user
            DELETE FROM comments WHERE user_id = p_user_id;

            -- Bước 4: Xóa comments của người khác trên bài của user này
            DELETE FROM comments WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);

            -- Bước 5: Xóa quan hệ bạn bè (2 chiều)
            DELETE FROM friends  WHERE user_id = p_user_id OR friend_id = p_user_id;

            -- Bước 6: Xóa bài viết (trigger tg_after_post_delete sẽ tự log)
            DELETE FROM posts    WHERE user_id = p_user_id;

            -- Bước 7: Xóa tài khoản
            DELETE FROM users    WHERE user_id = p_user_id;

        COMMIT;
        SET p_message = CONCAT('Thành công: Đã xóa hoàn toàn tài khoản user_id = ', p_user_id);
    END IF;
END$$

DELIMITER ;


-- ============================================================
-- PHẦN 5: DỮ LIỆU MẪU (ít nhất 3 users, 3 posts, tương tác)
-- ============================================================

INSERT INTO users (username, password, email) VALUES
('alice',   SHA2('alice123',   256), 'alice@example.com'),
('bob',     SHA2('bob123',     256), 'bob@example.com'),
('charlie', SHA2('charlie123', 256), 'charlie@example.com');

INSERT INTO posts (user_id, content) VALUES
(1, 'Chào mọi người! Đây là bài viết đầu tiên của Alice.'),
(2, 'Bob chia sẻ: MySQL Trigger thực sự rất mạnh và tiện lợi.'),
(3, 'Charlie: Transaction đảm bảo dữ liệu luôn nhất quán — cực kỳ quan trọng!');

-- Likes (trigger tg_after_like_insert sẽ tự tăng like_count)
INSERT INTO likes (user_id, post_id) VALUES
(2, 1),
(3, 1),
(1, 2),
(3, 2),
(1, 3);

-- Comments (trigger tg_after_comment_insert sẽ tự tăng comment_count)
INSERT INTO comments (post_id, user_id, content) VALUES
(1, 2, 'Chào Alice! Mình là Bob.'),
(1, 3, 'Xin chào từ Charlie!'),
(2, 1, 'Đồng ý với Bob, Trigger rất hay!'),
(3, 2, 'Transaction là nền tảng của DB nhỉ.');

-- Kết bạn (trigger tg_before_friend_insert kiểm tra trước khi INSERT)
INSERT INTO friends (user_id, friend_id, status) VALUES
(1, 2, 'accepted'),
(1, 3, 'accepted'),
(2, 3, 'pending');


-- ============================================================
-- PHẦN 6: KIỂM THỬ NHANH
-- ============================================================

-- Kiểm tra view_user_info (không có password)
SELECT * FROM view_user_info;

-- Kiểm tra like_count và comment_count đã được Trigger cập nhật
SELECT post_id, content, like_count, comment_count FROM posts;

-- Kiểm tra sp_add_user
CALL sp_add_user('diana', SHA2('diana123', 256), 'diana@example.com', @msg);
SELECT @msg;

-- Thử đăng ký trùng username
CALL sp_add_user('alice', SHA2('pass', 256), 'newalice@example.com', @msg);
SELECT @msg;

-- Thống kê hoạt động tất cả users
CALL sp_user_activity_report();

-- Kiểm tra trigger chặn tự kết bạn (sẽ báo lỗi SQLSTATE 45000)
-- INSERT INTO friends (user_id, friend_id, status) VALUES (1, 1, 'pending');

-- Kiểm tra trigger chặn đảo chiều (sẽ báo lỗi SQLSTATE 45001)
-- INSERT INTO friends (user_id, friend_id, status) VALUES (2, 1, 'pending');

SELECT post_id, content FROM posts
WHERE MATCH(content) AGAINST ('Trigger Transaction' IN BOOLEAN MODE);
