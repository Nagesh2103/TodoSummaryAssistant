import axios from 'axios';
import todoService from './todoService';

jest.mock('axios', () => ({
  __esModule: true,
  default: { get: jest.fn(), post: jest.fn(), put: jest.fn(), delete: jest.fn() },
}));

describe('todoService', () => {
  afterEach(() => jest.clearAllMocks());

  test('getAllTodos calls GET /api/todos', () => {
    todoService.getAllTodos();
    expect(axios.get).toHaveBeenCalledWith('/api/todos');
  });

  test('createTodo calls POST with payload', () => {
    const todo = { title: 't', description: 'd', completed: false };
    todoService.createTodo(todo);
    expect(axios.post).toHaveBeenCalledWith('/api/todos', todo);
  });

  test('updateTodo calls PUT /api/todos/:id', () => {
    todoService.updateTodo(5, { title: 'x' });
    expect(axios.put).toHaveBeenCalledWith('/api/todos/5', { title: 'x' });
  });

  test('deleteTodo calls DELETE /api/todos/:id', () => {
    todoService.deleteTodo(7);
    expect(axios.delete).toHaveBeenCalledWith('/api/todos/7');
  });

  test('summarizeTodos calls POST /api/todos/summarize', () => {
    todoService.summarizeTodos();
    expect(axios.post).toHaveBeenCalledWith('/api/todos/summarize');
  });
});
