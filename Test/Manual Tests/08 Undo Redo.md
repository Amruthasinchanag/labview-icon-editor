# Scope
This procedure is used to verify the undo/redo states are properly stored and applied appropriately.

Unless otherwise stated, each section of the Main may be ran independently of the other sections. The Setup and Cleanup must be performed.

An Undo action can be done through either the Edit menu or by pressing Ctrl+z.
A Redo action can be done through either the Edit menu or by pressing Ctrl+Shift+z.

# Setup
1. Open VI Template.vi.
2. Double-click on the icon to open the Icon Editor.
**NOTE:** This will add IE_Test.png to your list of templates.

# Main
## 1. Templates Tab
1. Open the Templates tab
2. Verify the Undo and Redo items in the Edit menu are disabled.
3. In the Filter Templates by Keyword control, type "i".
4. Verify the Undo item in the Edit menu is enabled.
5. Verify the Redo item in the Edit menu is disabled.
6. Verify the "_blank.png" templates are removed from the list.
7. Perform an undo.
8. Verify the string in Filter Templates by Keyword is now empty.
9. Verify the Undo item in the Edit menu is disabled.
10. Verify the Redo items in the Edit menu is enabled.
11. Verify the "_blank.png" templates are back in the list.
12. Perform a Redo.
13. Verify the string in Filter Templates by Keyword is now "i".
14. Verify the Undo item in the Edit menu is enabled.
15. Verify the Redo items in the Edit menu is disabled.
16. Verify the "_blank.png" templates are back removed from the list.


# Cleanup