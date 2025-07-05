const SidebarHook = {
  mounted() {
    this.setSidebarState = (open) => {
      localStorage.setItem("phx:sidebar", open ? "open" : "closed");
      if (open) {
        document.documentElement.classList.add("sidebar-open");
      } else {
        document.documentElement.classList.remove("sidebar-open");
      }
      this.el.checked = open;
    };

    const sidebarState = localStorage.getItem("phx:sidebar");
    if (sidebarState) {
      this.setSidebarState(sidebarState === "open");
    } else {
      this.setSidebarState(false); // Default to closed
    }

    this.el.addEventListener("change", (e) => {
      this.setSidebarState(e.target.checked);
    });

    window.addEventListener("storage", (e) => {
      if (e.key === "phx:sidebar") {
        this.setSidebarState(e.newValue === "open");
      }
    });
  },
};

export default SidebarHook;
