typedef HideRule = bool Function(
    {required bool linux, required String desktop, required bool screenReaderOn});

bool detect(HideRule rule) => false;
