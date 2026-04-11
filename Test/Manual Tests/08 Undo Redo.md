# Scope
This procedure is used to verify the undo/redo states are properly stored and applied appropriately.

Unless otherwise stated, each section of the Main may be ran independently of the other sections. The Setup and Cleanup must be performed.

An Undo action can be done through either the Edit menu or by pressing Ctrl+z.
A Redo action can be done through either the Edit menu or by pressing Ctrl+Shift+z.

# Setup
1. Open VI Template.vi.
**NOTE:** This will add IE_Test.png to your list of templates.

# Main
## 1. Templates Tab
1. Double-click on the icon on VI Template.vi to open the Icon Editor.
2. Open the Templates tab
3. Verify the Undo and Redo items in the Edit menu are disabled.
4. In the Filter Templates by Keyword control, type "ie".
5. Verify the Undo item in the Edit menu is enabled.
6. Verify the Redo item in the Edit menu is disabled.
7. Verify the "_blank.png" templates are removed from the list.
8. Perform an undo.
9. Verify the string in Filter Templates by Keyword is now "i".
10. Verify the Undo item in the Edit menu is enabled.
11. Verify the Redo items in the Edit menu is enabled.
12. Verify the "_blank.png" templates are still removed from the list.
13. Perform an undo.
14. Verify the string in the Filter Templates by Keyword is now empty.
15. Verify the Undo item in the Edit menu is disabled.
16. Verify the Redo items in the Edit menu is enabled.
17. Verify the "_blank.png" templates are back in the list.
18. Perform a redo.
19. Verify the string in Filter Templates by Keyword is now "i".
20. Verify the Undo item in the Edit menu is enabled.
21. Verify the Redo items in the Edit menu is enabled.
22. Verify the "_blank.png" templates are removed from the list.
23. Perform a redo.
24. Verify the Undo item in the Edit menu is enabled.
25. Verify the Redo item in the Edit menu is disabled.
26. Verify the "_blank.png" templates are still removed from the list.
27. Perform 2 undo actions to return to the default state.
28. Select the "VI\Frameworkds\_blank.png" template.
29. Verify the Undo item in the Edit menu is enabled.
30. Verify the Redo item in the Edit menu is disabled.
31. Perform an Undo.
32. Verify the used template is now "IE_Test.png".
33. Verify the Undo item in the Edit menu is disabled.
34. Verify the Redo item in the Edit menu is enabled.
35. Perform a Redo.
36. Verify the used template is now "_blank.png".
37. Verify the Undo item in the Edit menu is enabled.
38. Verify the Redo item in the Edit menu is disabled.
39. Close the Icon Editor, discarding any changes.

## 2. Icon Text Tab
1. Double-click on the icon on VI Template.vi to open the Icon Editor.
2. Open the Icon Text tab.
3. Verify the Undo and Redo items in the Edit menu are disabled.
4. In Line 1 text, type "ie".
5. Verify the Undo item in the Edit menu is enabled.
6. Verify the Redo item in the Edit menu is disabled.
7. Perform an undo.
8. Verify the string in Line 1 text is now "i".
9. Verify the Undo item in the Edit menu is enabled.
10. Verify the Redo items in the Edit menu is enabled.
11. Perorm an undo.
12. Verify the string in Line 1 text is now empty.
13. Verify the Undo item in the Edit menu is disabled.
14. Verify the Redo items in the Edit menu is enabled.
15. Perform a redo.
16. Verify the string in Line 1 text is now "i".
17. Verify the Undo item in the Edit menu is enabled.
18. Verify the Redo items in the Edit menu is enabled.
19. Perform a redo.
20. Verify the string in Line 1 text is now "ie".
21. Verify the Undo item in the Edit menu is enabled.
22. Verify the Redo items in the Edit menu is disabled.
23. Perform an undo.
24. In Line 2 text, type "a".
25. Verify the Undo item in the Edit menu is enabled.
26. Verify the Redo items in the Edit menu is disabled.
27. Perform an undo.
28. Verify Line 2 text is empty.
29. Perfrom a redo.
30. Verify Line 2 text is "a".
31. In Line 3 text, type "b".
32. Perform an undo.
33. Verify Line 3 text is empty.
34. Perfrom a redo.
35. Verify Line 3 text is "b".
36. In Line 4 text, type "c".
37. Perform an undo.
38. Verify Line 4 text is empty.
39. Perform a redo.
40. Verify Line 4 text is "c".
41. Set Line 1 color to LED On.
42. Perform an undo.
43. Verify Line 1 color is black.
44. Perform a redo.
45. Verify Line 1 color is LED On.
46. Perform an undo.
47. Set Line 2 color to LED On.
48. Perform an undo.
49. Verify Line 2 color is black.
50. Perform a redo.
51. Verify Line 2 color is LED On.
52. Perform an undo.
53. Set Line 3 color to LED On.
54. Perform an undo.
55. Verify Line 3 color is black.
56. Perform a redo.
57. Verify Line 3 color is LED On.
58. Perform an undo.
59. Set Line 4 color to LED On.
60. Perform an undo.
61. Verify Line 4 color is black.
62. Perform a redo.
63. Verify Line 4 color is LED On.
64. Perform an undo.
65. Set the Font to LabVIEW Application.
66. Perform an undo.
67. Verify the Font is Small Fonts.
68. Perform a redo.
69. Verify the Font is LabVIEW Application.
70. Perform an undo.
71. Set Alignment to left.
72. Perform an undo.
73. Verify Alignment is center.
74. Perform a redo.
75. Verify Alignmnet is left.
76. Perform an undo.
77. Set the font size to 10.
78. Perform an undo.
79. Verify the font size is 9.
80. Perform a redo.
81. Verify the font size is 10.
82. Perform an undo.
83. Uncheck Center text vertically.
84. Perform an undo.
85. Verify the Center text vertically is checked.
86. Perform a redo.
87. Verify the Center text vertically is unchecked.
88. Perform an undo.
89. Check the Capitalize text.
90. Perform an undo.
91. Verify the Captialize text is unchecked.
92. Perform a redo.
93. Verify the Capitalize text is checked.
94. Close the Icon Editor, discarding any changes.

## 3. Glyphs Tab
1. Double-click on the icon on VI Template.vi to open the Icon Editor.
2. Open the Glyphs tab.
3. Verify the Undo and Redo items in the Edit menu are disabled.
3. In the Filter glyphs by keyword control, type "xy".
4. Verify the Undo item in the Edit menu is enabled.
5. Verify the Redo item in the Edit menu is disabled.
6. Perform an undo.
7. Verify the string in Filter glyphs by keyword is now "x".
8. Verify the filtered list of glyphs was updated.
9. Verify the Undo item in the Edit menu is enabled.
10. Verify the Redo item in the Edit menu is enabled.
11. Perform an undo.
12. Verify the string in Filter glyphs by keyword is now empty.
13. Verify the filtered list of glyphs was updated.
14. Verify the Undo item in the Edit menu is disabled.
15. Verify the Redo item in the Edit menu is enabled.
16. Perform a redo.
17. Verify the string in Filter glyphs by keyword is now "x".
18. Verify the filtered list of glyphs was updated.
19. Verify the Undo item in the Edit menu is enabled.
20. Verify the Redo item in the Edit menu is enabled.
21. Perform a redo.
22. Verify the string in Filter glyphs by keyword is now "xy".
23. Verify the filtered list of glyphs was updated.
24. Verify the Undo item in the Edit menu is disabled.
25. Verify the Redo item in the Edit menu is enabled.
26. Double-click the xy_graph glyph to place it in the icon.
27. Perform an undo.
28. Verify the glyph was removed from the icon.
29. Perform a redo.
30. Verify the glyph was placed backed in the icon.
31. Close the Icon Editor, discarding any changes.

# Cleanup
1. Click "Cancel" to close the Icon Editor, discarding any changes.
2. Close the VI Template.vi, discarding any changes.