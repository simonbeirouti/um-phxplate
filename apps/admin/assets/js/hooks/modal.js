const Modal = {
  mounted() {
    this.el.addEventListener("show", (e) => {
      this.el.showModal();
    });

    this.handleEvent("close-modal", ({ id }) => {
      if (this.el.id === id) {
        this.el.close();
      }
    });
  },
};

export default Modal;
