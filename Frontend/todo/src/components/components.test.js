import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import TodoForm from './TodoForm';
import TodoList from './TodoList';
import Notification from './Notification';

describe('Notification', () => {
  test('renders nothing without a message', () => {
    const { container } = render(<Notification message="" type="" />);
    expect(container).toBeEmptyDOMElement();
  });

  test('renders message with type class', () => {
    render(<Notification message="Saved" type="success" />);
    expect(screen.getByText('Saved')).toHaveClass('notification', 'success');
  });
});

describe('TodoForm', () => {
  test('submits a new todo', () => {
    const addTodo = jest.fn();
    render(<TodoForm addTodo={addTodo} updateTodo={jest.fn()} editingTodo={null} setEditingTodo={jest.fn()} />);
    fireEvent.change(screen.getByPlaceholderText('Todo Title'), { target: { value: 'Buy milk' } });
    fireEvent.change(screen.getByPlaceholderText('Todo Description (Optional)'), { target: { value: '2L' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add Todo' }));
    expect(addTodo).toHaveBeenCalledWith({ title: 'Buy milk', description: '2L', completed: false });
  });

  test('does not submit a blank title', () => {
    const addTodo = jest.fn();
    render(<TodoForm addTodo={addTodo} updateTodo={jest.fn()} editingTodo={null} setEditingTodo={jest.fn()} />);
    fireEvent.change(screen.getByPlaceholderText('Todo Title'), { target: { value: '   ' } });
    fireEvent.submit(screen.getByRole('button', { name: 'Add Todo' }).closest('form'));
    expect(addTodo).not.toHaveBeenCalled();
  });

  test('edit mode calls updateTodo and clears editing state', () => {
    const updateTodo = jest.fn();
    const setEditingTodo = jest.fn();
    const editing = { id: 4, title: 'Old', description: 'desc', completed: false };
    render(<TodoForm addTodo={jest.fn()} updateTodo={updateTodo} editingTodo={editing} setEditingTodo={setEditingTodo} />);
    expect(screen.getByPlaceholderText('Todo Title')).toHaveValue('Old');
    fireEvent.click(screen.getByLabelText('Completed'));
    fireEvent.click(screen.getByRole('button', { name: 'Update Todo' }));
    expect(updateTodo).toHaveBeenCalledWith(4, { title: 'Old', description: 'desc', completed: true });
    expect(setEditingTodo).toHaveBeenCalledWith(null);
  });
});

describe('TodoList', () => {
  const todos = [
    { id: 1, title: 'A', description: 'a', completed: false },
    { id: 2, title: 'B', description: 'b', completed: true },
  ];

  test('renders todos and completed styling', () => {
    render(<TodoList todos={todos} deleteTodo={jest.fn()} setEditingTodo={jest.fn()} toggleComplete={jest.fn()} />);
    expect(screen.getByText('A')).toBeInTheDocument();
    expect(screen.getByText('B').closest('.todo-item')).toHaveClass('completed');
    expect(screen.getByText('Mark Complete')).toBeInTheDocument();
    expect(screen.getByText('Mark Pending')).toBeInTheDocument();
  });

  test('action buttons call handlers with the right args', () => {
    const deleteTodo = jest.fn();
    const setEditingTodo = jest.fn();
    const toggleComplete = jest.fn();
    render(<TodoList todos={todos} deleteTodo={deleteTodo} setEditingTodo={setEditingTodo} toggleComplete={toggleComplete} />);
    fireEvent.click(screen.getAllByText('Delete')[0]);
    fireEvent.click(screen.getAllByText('Edit')[1]);
    fireEvent.click(screen.getByText('Mark Complete'));
    expect(deleteTodo).toHaveBeenCalledWith(1);
    expect(setEditingTodo).toHaveBeenCalledWith(todos[1]);
    expect(toggleComplete).toHaveBeenCalledWith(1, true);
  });
});
