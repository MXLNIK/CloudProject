-- Сотрудники организации
CREATE TABLE IF NOT EXISTS employees (
    id        SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    position  VARCHAR(100) NOT NULL DEFAULT 'сотрудник'
);

-- Проекты
CREATE TABLE IF NOT EXISTS projects (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    description VARCHAR(500) NOT NULL DEFAULT '',
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Задачи
CREATE TABLE IF NOT EXISTS tasks (
    id          SERIAL PRIMARY KEY,
    project_id  INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title       VARCHAR(200) NOT NULL,
    status      VARCHAR(20)  NOT NULL DEFAULT 'новая',
    assignee_id INT REFERENCES employees(id) ON DELETE SET NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Индексы для частых выборок
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks (project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee   ON tasks (assignee_id);

-- Демо-данные: добавляются только в пустые таблицы
INSERT INTO employees (full_name, position)
SELECT 'Иванов Иван', 'руководитель проектов'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE full_name = 'Иванов Иван');

INSERT INTO employees (full_name, position)
SELECT 'Петрова Анна', 'дизайнер'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE full_name = 'Петрова Анна');

INSERT INTO employees (full_name, position)
SELECT 'Сидоров Сергей', 'веб-разработчик'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE full_name = 'Сидоров Сергей');

INSERT INTO employees (full_name, position)
SELECT 'Кузнецова Ольга', 'тестировщик'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE full_name = 'Кузнецова Ольга');

-- Демонстрационный проект
INSERT INTO projects (name, description)
SELECT 'Разработка сайта',
       'Демонстрационный проект, создан автоматически при инициализации базы данных'
WHERE NOT EXISTS (SELECT 1 FROM projects);

-- Три задачи в демонстрационном проекте
INSERT INTO tasks (project_id, title, status, assignee_id)
SELECT p.id, v.title, v.status, e.id
FROM projects p
CROSS JOIN (VALUES
    ('Создать дизайн',               'новая',     'Петрова Анна'),
    ('Разработать главную страницу', 'в работе',   'Сидоров Сергей'),
    ('Проверить сайт',               'выполнена', 'Кузнецова Ольга')
) AS v(title, status, full_name)
LEFT JOIN employees e ON e.full_name = v.full_name
WHERE p.name = 'Разработка сайта'
  AND NOT EXISTS (SELECT 1 FROM tasks WHERE project_id = p.id);
