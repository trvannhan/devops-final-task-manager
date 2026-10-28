const $ = (id) => document.getElementById(id);
const notice = (msg) => {
  $("notice").textContent = msg || "";
};
async function api(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    let body = {};
    try {
      body = await response.json();
    } catch {}
    throw Error(body.error || `HTTP ${response.status}`);
  }
  return response.status === 204 ? null : response.json();
}
async function refresh() {
  try {
    const items = await api("/api/tasks");
    $("total").textContent = items.length;
    $("pending").textContent = items.filter((x) => !x.completed).length;
    $("completed").textContent = items.filter((x) => x.completed).length;
    const list = $("taskList");
    list.replaceChildren();
    if (items.length === 0) {
      const e = document.createElement("div");
      e.className = "empty";
      e.textContent = "Chưa có công việc nào. Hãy tạo công việc đầu tiên!";
      list.append(e);
    }
    for (const t of items) {
      const row = document.createElement("div");
      row.className = "task" + (t.completed ? " done" : "");
      const left = document.createElement("div");
      left.className = "task-left";
      const label = document.createElement("div");
      const title = document.createElement("div");
      title.className = "task-title";
      title.textContent = t.title;
      const desc = document.createElement("div");
      desc.className = "task-desc";
      desc.textContent = t.description || "Không có mô tả";
      label.append(title, desc);
      left.append(label);
      const actions = document.createElement("div");
      actions.className = "task-actions";
      const toggle = document.createElement("button");
      toggle.textContent = t.completed ? "↺ Làm lại" : "✓ Hoàn thành";
      toggle.onclick = async () => {
        try {
          await api("/api/tasks/" + t.id, {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ completed: !t.completed }),
          });
          notice("");
          refresh();
        } catch (e) {
          notice(e.message);
        }
      };
      const del = document.createElement("button");
      del.className = "danger";
      del.textContent = "Xóa";
      del.onclick = async () => {
        if (!confirm("Xóa công việc này?")) return;
        try {
          await api("/api/tasks/" + t.id, { method: "DELETE" });
          notice("");
          refresh();
        } catch (e) {
          notice(e.message);
        }
      };
      actions.append(toggle, del);
      row.append(left, actions);
      list.append(row);
    }
  } catch (e) {
    notice("Không thể tải task: " + e.message);
  }
}
$("taskForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const title = $("title").value.trim(),
    description = $("description").value.trim();
  if (!title) return;
  const button = $("addBtn");
  button.disabled = true;
  try {
    await api("/api/tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description }),
    });
    $("taskForm").reset();
    notice("");
    await refresh();
  } catch (e) {
    notice("Lỗi thêm task: " + e.message);
  } finally {
    button.disabled = false;
  }
});
fetch("/health")
  .then((r) => r.json())
  .then((x) => {
    $("health").textContent =
      (x.status === "ok" ? "● Database connected" : "● Database unavailable") +
      (x.version ? " · v" + x.version : "");
  })
  .catch(() => {
    $("health").textContent = "● Service unavailable";
  });
refresh();
