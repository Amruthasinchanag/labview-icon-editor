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
3. In the Filter Templates by Keyword control, type "ie".
4. Verify the Undo item in the Edit menu is enabled.
5. Verify the Redo item in the Edit menu is disabled.
6. Verify the "_blank.png" templates are removed from the list.
7. Perform an undo.
8. Verify the string in Filter Templates by Keyword is now "i".
9. Verify the Undo item in the Edit menu is enabled.
10. Verify the Redo items in the Edit menu is enabled.
11. Verify the "_blank.png" templates are still removed from the list.
12. Perform an undo.
13. Verify the string in the Filter Templates by Keyword is now empty.
14. Verify the Undo item in the Edit menu is disabled.
15. Verify the Redo items in the Edit menu is enabled.
11. Verify the "_blank.png" templates are back in the list.
12. Perform a redo.
13. Verify the string in Filter Templates by Keyword is now "i".
14. Verify the Undo item in the Edit menu is enabled.
15. Verify the Redo items in the Edit menu is enabled.
16. Verify the "_blank.png" templates are removed from the list.
17. Perform a redo.
18. Verify the Undo item in the Edit menu is enabled.
19. Verify the Redo item in the Edit menu is disabled.
20. Verify the "_blank.png" templates are still removed from the list.
21. Perform 2 undo actions to return to the default state.
22. Select the "VI\Frameworkds\_blank.png" template.
23. Verify the Undo item in the Edit menu is enabled.
24. Verify the Redo item in the Edit menu is disabled.
25. Perform an Undo.
26. Verify the used template is now "IE_Test.png".
27. Verify the Undo item in the Edit menu is disabled.
28. Verify the Redo item in the Edit menu is enabled.
29. Perform a Redo.
30. Verify the used template is now "_blank.png".
31. Verify the Undo item in the Edit menu is enabled.
32. Verify the Redo item in the Edit menu is disabled.
33. Perform an undo to return to the default state.

# Cleanup