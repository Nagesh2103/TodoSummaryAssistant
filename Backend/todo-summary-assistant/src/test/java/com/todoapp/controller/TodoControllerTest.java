package com.todoapp.controller;

import com.todoapp.entity.Todo;
import com.todoapp.service.CohereService;
import com.todoapp.service.SlackService;
import com.todoapp.service.TodoService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Controller slice tests: HTTP contract with all collaborators mocked. */
@WebMvcTest(TodoController.class)
class TodoControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private TodoService todoService;
    @MockitoBean
    private CohereService cohereService;
    @MockitoBean
    private SlackService slackService;

    @Test
    void getAll_returns200AndJsonList() throws Exception {
        when(todoService.getAllTodos()).thenReturn(List.of(new Todo(1L, "d", "t", false)));
        mockMvc.perform(get("/api/todos"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].title").value("t"))
                .andExpect(jsonPath("$[0].completed").value(false));
    }

    @Test
    void create_returns201() throws Exception {
        when(todoService.createTodo(any(Todo.class))).thenReturn(new Todo(3L, "d", "t", false));
        mockMvc.perform(post("/api/todos").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"t\",\"description\":\"d\",\"completed\":false}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(3));
    }

    @Test
    void update_returns200() throws Exception {
        when(todoService.updateTodo(eq(1L), any(Todo.class))).thenReturn(new Todo(1L, "d", "t2", true));
        mockMvc.perform(put("/api/todos/1").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"t2\",\"description\":\"d\",\"completed\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.completed").value(true));
    }

    @Test
    void delete_returns204() throws Exception {
        mockMvc.perform(delete("/api/todos/1")).andExpect(status().isNoContent());
        verify(todoService).deleteTodo(1L);
    }

    @Test
    void summarize_noPending_returnsMessage_andSkipsExternalCalls() throws Exception {
        when(todoService.getPendingTodos()).thenReturn(List.of());
        mockMvc.perform(post("/api/todos/summarize"))
                .andExpect(status().isOk())
                .andExpect(content().string("No pending todos to summarize."));
        verifyNoInteractions(cohereService, slackService);
    }

    @Test
    void summarize_success_sendsToSlack() throws Exception {
        when(todoService.getPendingTodos()).thenReturn(List.of(new Todo(1L, "d", "t", false)));
        when(cohereService.summarizeText(anyString())).thenReturn("short summary");
        when(slackService.sendSlackMessage(anyString())).thenReturn(true);

        mockMvc.perform(post("/api/todos/summarize"))
                .andExpect(status().isOk())
                .andExpect(content().string("Summary generated and sent to Slack successfully!"));
        verify(slackService).sendSlackMessage("Todo Summary:\nshort summary");
    }

    @Test
    void summarize_slackFails_returns500() throws Exception {
        when(todoService.getPendingTodos()).thenReturn(List.of(new Todo(1L, "d", "t", false)));
        when(cohereService.summarizeText(anyString())).thenReturn("s");
        when(slackService.sendSlackMessage(anyString())).thenReturn(false);

        mockMvc.perform(post("/api/todos/summarize"))
                .andExpect(status().isInternalServerError())
                .andExpect(content().string("Failed to send summary to Slack."));
    }

    @Test
    void summarize_cohereFails_returns500_andDoesNotCallSlack() throws Exception {
        when(todoService.getPendingTodos()).thenReturn(List.of(new Todo(1L, "d", "t", false)));
        when(cohereService.summarizeText(anyString())).thenThrow(new IOException("cohere down"));

        mockMvc.perform(post("/api/todos/summarize"))
                .andExpect(status().isInternalServerError());
        verifyNoInteractions(slackService);
    }
}
