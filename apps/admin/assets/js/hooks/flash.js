const Flash = {
  mounted() {
    const flash = this.el;
    const key = flash.dataset.key;
    setTimeout(() => {
      this.pushEvent("lv:clear-flash", { key: key });
    }, 1500);
  }
};

export default Flash;
