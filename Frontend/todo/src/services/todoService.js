import axios from 'axios';

// Springboot backend url.
// DevOps enablement: configurable at build time via REACT_APP_API_BASE_URL.
// Default is the relative path "/api" so the same image works everywhere:
// nginx (production) and the CRA dev proxy (local) both forward /api to the backend.
const API_BASE_URL = `${process.env.REACT_APP_API_BASE_URL || '/api'}/todos`;

const todoService = {
  getAllTodos: () => axios.get(API_BASE_URL),
  createTodo: (todo) => axios.post(API_BASE_URL, todo),
  updateTodo: (id, todo) => axios.put(`${API_BASE_URL}/${id}`, todo),
  deleteTodo: (id) => axios.delete(`${API_BASE_URL}/${id}`),
  summarizeTodos: () => axios.post(`${API_BASE_URL}/summarize`),
};

export default todoService;
