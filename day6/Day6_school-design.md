School Database Design

# Tables

- **students** stores each student's name and unique email address.
- **courses** stores course names and unique course codes.
- **enrolments** links students to courses and stores each enrolment's grade.

# Relationships

A student can have many enrolments, and a course can have many enrolments. These are one-to-many relationships between `students` and `enrolments`, and between `courses` and `enrolments`. Students and courses have a many-to-many relationship: each student can take several courses, and each course can have several students. The `enrolments` join table connects them and stores details about each enrolment, such as the grade.

# Index

I would add an index on `enrolments(course_id)` to help the database find students in a course and count enrolments more quickly.

# SQL or NoSQL?

I would choose SQL for this system because the data has clear relationships and needs to stay consistent. Foreign keys and unique constraints help prevent invalid or duplicate records, while joins make it easy to retrieve information about students, courses, and grades.
