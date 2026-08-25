const AUTH_URL = 'http://localhost:4001';
const BACKEND_URL = 'http://localhost:4000';

let token = sessionStorage.getItem('secureTasksToken');
let currentUser = JSON.parse(sessionStorage.getItem('secureTasksUser') || 'null');

const loginCard = document.getElementById('loginCard');
const appCard = document.getElementById('appCard');
const welcome = document.getElementById('welcome');
const statusEl = document.getElementById('status');
const taskList = document.getElementById('taskList');
const adminSection = document.getElementById('adminSection');

function setStatus(message) {
  statusEl.textContent = message;
}

async function login() {
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;

  setStatus('Logging in...');

  const response = await fetch(`${AUTH_URL}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  });

  const data = await response.json();
  if (!response.ok) {
    setStatus(data.error || 'Login failed');
    return;
  }

  token = data.token;
  currentUser = data.user;
  sessionStorage.setItem('secureTasksToken', token);
  sessionStorage.setItem('secureTasksUser', JSON.stringify(currentUser));
  showApp();
  await loadTasks();
}

async function loadTasks() {
  const response = await fetch(`${BACKEND_URL}/tasks`, {
    headers: { Authorization: `Bearer ${token}` }
  });

  const data = await response.json();

  if (!response.ok) {
    setStatus(data.error || 'Request failed');
    return;
  }

  taskList.innerHTML = '';
  for (const task of data.tasks) {
    const li = document.createElement('li');
    li.textContent = task.title;
    taskList.appendChild(li);
  }
}

async function addTask() {
  const titleInput = document.getElementById('newTask');
  const title = titleInput.value.trim();
  if (!title) return;

  const response = await fetch(`${BACKEND_URL}/tasks`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({ title })
  });

  const data = await response.json();
  if (!response.ok) {
    setStatus(data.error || 'Failed to add task');
    return;
  }

  titleInput.value = '';
  setStatus('Task added');
  await loadTasks();
}

async function callAdmin() {
  const response = await fetch(`${BACKEND_URL}/admin`, {
    headers: { Authorization: `Bearer ${token}` }
  });

  const data = await response.json();
  document.getElementById('adminResult').textContent =
    `HTTP ${response.status}\n${JSON.stringify(data, null, 2)}`;
}

function logout() {
  token = null;
  currentUser = null;
  sessionStorage.removeItem('secureTasksToken');
  sessionStorage.removeItem('secureTasksUser');
  showLogin();
}

function showApp() {
  loginCard.classList.add('hidden');
  appCard.classList.remove('hidden');
  welcome.textContent = `Welcome, ${currentUser.username} (${currentUser.role})`;
  adminSection.classList.toggle('hidden', currentUser.role !== 'admin');
  setStatus('');
}

function showLogin() {
  loginCard.classList.remove('hidden');
  appCard.classList.add('hidden');
  taskList.innerHTML = '';
}

document.getElementById('loginBtn').addEventListener('click', login);
document.getElementById('logoutBtn').addEventListener('click', logout);
document.getElementById('addTaskBtn').addEventListener('click', addTask);
document.getElementById('adminBtn').addEventListener('click', callAdmin);

if (token && currentUser) {
  showApp();
  loadTasks();
} else {
  showLogin();
}
