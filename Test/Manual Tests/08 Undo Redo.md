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

## 2. Icon Text Tab
1. Open the Icon Text tab.
2. Verify the Undo and Redo items in the Edit menu are disabled.
3. In Line 1 text, type "ie".
4. Verify the Undo item in the Edit menu is enabled.
5. Verify the Redo item in the Edit menu is disabled.
6. Perform an undo.
7. Verify the string in Line 1 text is now "i".
8. Verify the Undo item in the Edit menu is enabled.
9. Verify the Redo items in the Edit menu is enabled.
10. Perorm an undo.
11. Verify the string in Line 1 text is now empty.
12. Verify the Undo item in the Edit menu is disabled.
13. Verify the Redo items in the Edit menu is enabled.
14. Perform a redo.
15. Verify the string in Line 1 text is now "i".
16. Verify the Undo item in the Edit menu is enabled.
17. Verify the Redo items in the Edit menu is enabled.
18. Perform a redo.
19. Verify the string in Line 1 text is now "ie".
20. Verify the Undo item in the Edit menu is enabled.
21. Verify the Redo items in the Edit menu is disabled.
22. Perform an undo.
23. In Line 2 text, type "a".
24. Verify the Undo item in the Edit menu is enabled.
25. Verify the Redo items in the Edit menu is disabled.
26. Perform an undo.
27. Verify Line 2 text is empty.
28. Perfrom a redo.
29. Verify Line 2 text is "a".
30. In Line 3 text, type "b".
31. Perform an undo.
32. Verify Line 3 text is empty.
33. Perfrom a redo.
34. Verify Line 3 text is "b".
35. In Line 4 text, type "c".
36. Perform an undo.
37. Verify Line 4 text is empty.
38. Perform a redo.
39. Verify Line 4 text is "c".
40. Set Line 1 color to LED On.
41. Perform an undo.
42. Verify Line 1 color is black.
43. Perform a redo.
44. Verify Line 1 color is LED On.
45. Perform an undo.
46. Set Line 2 color to LED On.
47. Perform an undo.
48. Verify Line 2 color is black.
49. Perform a redo.
50. Verify Line 2 color is LED On.
51. Perform an undo.
52. Set Line 3 color to LED On.
53. Perform an undo.
54. Verify Line 3 color is black.
55. Perform a redo.
56. Verify Line 3 color is LED On.
57. Perform an undo.
58. Set Line 4 color to LED On.
59. Perform an undo.
60. Verify Line 4 color is black.
61. Perform a redo.
62. Verify Line 4 color is LED On.
63. Perform an undo.
64. Set the Font to LabVIEW Application.
65. Perform an undo.
66. Verify the Font is Small Fonts.
67. Perform a redo.
68. Verify the Font is LabVIEW Application.
69. Perform an undo.
70. Set Alignment to left.
71. Perform an undo.
72. Verify Alignment is center.
73. Perform a redo.
74. Verify Alignmnet is left.
75. Perform an undo.
76. Set the font size to 10.
77. Perform an undo.
78. Verify the font size is 9.
79. Perform a redo.
80. Verify the font size is 10.
81. Perform an undo.
82. Uncheck Center text vertically.
83. Perform an undo.
84. Verify the Center text vertically is checked.
85. Perform a redo.
86. Verify the Center text vertically is unchecked.
87. Perform an undo.
88. Check the Capitalize text.
89. Perform an undo.
90. Verify the Captialize text is unchecked.
91. Perform a redo.
92. Verify the Capitalize text is checked.
93. 


# Cleanup
1. Click "Cancel" to close the Icon Editor, discarding any changes.
2. Close the VI Template.vi, discarding any changes.