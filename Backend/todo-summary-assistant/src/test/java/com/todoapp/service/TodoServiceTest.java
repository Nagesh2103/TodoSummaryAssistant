package com.todoapp.service;

import com.todoapp.entity.Todo;
import com.todoapp.repository.TodoRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TodoServiceTest {

    @Mock
    private TodoRepository repository;

    @InjectMocks
    private TodoService service;

    private Todo todo(Long id, String title, boolean done) {
        return new Todo(id, "desc " + title, title, done);
    }

    @Test
    void getAllTodos_returnsEverything() {
        when(repository.findAll()).thenReturn(List.of(todo(1L, "a", false), todo(2L, "b", true)));
        assertEquals(2, service.getAllTodos().size());
    }

    @Test
    void getTodoById_found_and_notFound() {
        when(repository.findById(1L)).thenReturn(Optional.of(todo(1L, "a", false)));
        when(repository.findById(9L)).thenReturn(Optional.empty());
        assertTrue(service.getTodoById(1L).isPresent());
        assertTrue(service.getTodoById(9L).isEmpty());
    }

    @Test
    void createTodo_savesAndReturns() {
        Todo input = todo(null, "new", false);
        when(repository.save(input)).thenReturn(todo(5L, "new", false));
        assertEquals(5L, service.createTodo(input).getId());
    }

    @Test
    void updateTodo_updatesFields() {
        Todo existing = todo(1L, "old", false);
        when(repository.findById(1L)).thenReturn(Optional.of(existing));
        when(repository.save(any(Todo.class))).thenAnswer(i -> i.getArgument(0));

        Todo result = service.updateTodo(1L, todo(null, "new", true));

        assertEquals("new", result.getTitle());
        assertEquals("desc new", result.getDescription());
        assertTrue(result.isCompleted());
    }

    @Test
    void updateTodo_missing_throws() {
        when(repository.findById(42L)).thenReturn(Optional.empty());
        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.updateTodo(42L, todo(null, "x", false)));
        assertTrue(ex.getMessage().contains("42"));
        verify(repository, never()).save(any());
    }

    @Test
    void deleteTodo_existing_deletes() {
        Todo existing = todo(1L, "a", false);
        when(repository.findById(1L)).thenReturn(Optional.of(existing));
        service.deleteTodo(1L);
        verify(repository).delete(existing);
    }

    @Test
    void deleteTodo_missing_throws() {
        when(repository.findById(7L)).thenReturn(Optional.empty());
        assertThrows(RuntimeException.class, () -> service.deleteTodo(7L));
        verify(repository, never()).delete(any());
    }

    @Test
    void getPendingTodos_usesCompletedFalseQuery() {
        when(repository.findByCompletedFalse()).thenReturn(List.of(todo(1L, "a", false)));
        assertEquals(1, service.getPendingTodos().size());
        verify(repository).findByCompletedFalse();
    }
}
