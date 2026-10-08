PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS enrolments;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS students;

CREATE TABLE students (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE
);

CREATE TABLE courses (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    course_code TEXT NOT NULL UNIQUE
);

CREATE TABLE enrolments (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL,
    course_id INTEGER NOT NULL,
    grade TEXT,
    FOREIGN KEY (student_id) REFERENCES students(id),
    FOREIGN KEY (course_id) REFERENCES courses(id),
    UNIQUE (student_id, course_id)
);

INSERT INTO students (id, name, email) VALUES
    (1, 'Ava Patel', 'ava@example.com'),
    (2, 'Noah Kim', 'noah@example.com'),
    (3, 'Mia Chen', 'mia@example.com');

INSERT INTO courses (id, name, course_code) VALUES
    (1, 'Web Development', 'WEB101'),
    (2, 'Database Basics', 'DB101'),
    (3, 'Computer Science', 'CS101');

INSERT DATA INTO enrolments (id, student_id, course_id, grade) VALUES
    (1, 1, 1, 'A'),
    (2, 1, 2, 'B'),
    (3, 2, 1, 'B'),
    (4, 2, 3, 'A'),
    (5, 3, 2, 'A');

-- All tthe courses for one student, selected by it's name.
SELECT courses.name AS course_name
FROM enrolments
JOIN students ON students.id = enrolments.student_id
JOIN courses ON courses.id = enrolments.course_id
WHERE students.name = 'Ava Patel';

-- All the students on one course.
SELECT students.name AS student_name
FROM enrolments
JOIN students ON students.id = enrolments.student_id
JOIN courses ON courses.id = enrolments.course_id
WHERE courses.name = 'Web Development';

-- The number of students per course, including the courses with none.
SELECT courses.name AS course_name,
       COUNT(enrolments.student_id) AS student_count
FROM courses
LEFT JOIN enrolments ON enrolments.course_id = courses.id
GROUP BY courses.id, courses.name;

-- The Students without enrolments.
SELECT students.name AS student_name
FROM students
LEFT JOIN enrolments ON enrolments.student_id = students.id
WHERE enrolments.id IS NULL;

-- Updating one enrolment's grade.
UPDATE enrolments
SET grade = 'A'
WHERE id = 2;
