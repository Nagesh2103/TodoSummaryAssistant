import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import App from './App';
import todoService from './services/todoService';

jest.mock('./services/todoService', () => ({
  __esModule: true,
  default: {
    getAllTodos: jest.fn(),
    createTodo: jest.fn(),
    updateTodo: jest.fn(),
    deleteTodo: jest.fn(),
    summarizeTodos: jest.fn(),
  },
}));

describe('App', () => {
  beforeEach(() => {
    todoService.getAllTodos.mockResolvedValue({ data: [{ id: 1, title: 'First', description: 'd', completed: false }] });
  });
  afterEach(() => jest.clearAllMocks());

  test('loads and shows todos on mount', async () => {
    render(<App />);
    expect(await screen.findByText('First')).toBeInTheDocument();
    expect(todoService.getAllTodos).toHaveBeenCalledTimes(1);
  });

  test('shows an error notification when loading fails', async () => {
    todoService.getAllTodos.mockRejectedValue(new Error('boom'));
    jest.spyOn(console, 'error').mockImplementation(() => {});
    render(<App />);
    expect(await screen.findByText('Error fetching todos.')).toBeInTheDocument();
  });

  test('adds a todo and shows success notification', async () => {
    todoService.createTodo.mockResolvedValue({ data: { id: 2, title: 'Second', description: '', completed: false } });
    render(<App />);
    await screen.findByText('First');
    fireEvent.change(screen.getByPlaceholderText('Todo Title'), { target: { value: 'Second' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add Todo' }));
    expect(await screen.findByText('Todo added successfully!')).toBeInTheDocument();
    expect(await screen.findByText('Second')).toBeInTheDocument();
  });

  test('deletes a todo', async () => {
    todoService.deleteTodo.mockResolvedValue({});
    render(<App />);
    await screen.findByText('First');
    fireEvent.click(screen.getByText('Delete'));
    await waitFor(() => expect(screen.queryByText('First')).not.toBeInTheDocument());
    expect(screen.getByText('Todo deleted successfully!')).toBeInTheDocument();
  });

  test('summarize button shows backend message', async () => {
    todoService.summarizeTodos.mockResolvedValue({ data: 'Summary generated and sent to Slack successfully!' });
    render(<App />);
    await screen.findByText('First');
    fireEvent.click(screen.getByText(/Summarize Pending Todos/));
    expect(await screen.findByText('Summary generated and sent to Slack successfully!')).toBeInTheDocument();
  });

  test('summarize failure shows error notification', async () => {
    todoService.summarizeTodos.mockRejectedValue(new Error('x'));
    jest.spyOn(console, 'error').mockImplementation(() => {});
    render(<App />);
    await screen.findByText('First');
    fireEvent.click(screen.getByText(/Summarize Pending Todos/));
    expect(await screen.findByText('Failed to summarize and send to Slack.')).toBeInTheDocument();
  });
});
