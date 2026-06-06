// Copyright 2018 The Gitea Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package activities_test

import (
	"crypto/sha1"
	"fmt"
	"testing"
	"time"

	activities_model "code.gitea.io/gitea/models/activities"
	"code.gitea.io/gitea/models/db"
	"code.gitea.io/gitea/models/organization"
	"code.gitea.io/gitea/models/unittest"
	user_model "code.gitea.io/gitea/models/user"
	"code.gitea.io/gitea/modules/json"
	"code.gitea.io/gitea/modules/timeutil"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetUserHeatmapDataByUser(t *testing.T) {
	require.NoError(t, unittest.PrepareTestDatabase())
	require.NoError(t, db.TruncateBeans(t.Context(), &activities_model.HeatmapContribution{}))
	require.NoError(t, user_model.SetIncludePrivateContributions(t.Context(), 2, false))

	// Mock time
	timeutil.MockSet(time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC))
	defer timeutil.MockUnset()

	insertHeatmapContribution(t, 2, 1, "user2-public-author-date", 1603009800)
	insertHeatmapContribution(t, 2, 1, "user2-public-same-bucket", 1603009850)
	insertHeatmapContribution(t, 2, 2, "user2-private-hidden", 1603010700)
	insertHeatmapContribution(t, 3, 1, "other-author-ignored", 1603010700)

	testCases := []struct {
		desc        string
		userID      int64
		doerID      int64
		CountResult int
		JSONResult  string
	}{
		{
			"self sees public author-date contributions only",
			2, 2, 2, `[{"timestamp":1603009800,"contributions":2}]`,
		},
		{
			"admin sees public author-date contributions only",
			2, 1, 2, `[{"timestamp":1603009800,"contributions":2}]`,
		},
		{
			"other user sees public author-date contributions only",
			2, 3, 2, `[{"timestamp":1603009800,"contributions":2}]`,
		},
		{
			"anonymous sees public author-date contributions only",
			2, 0, 2, `[{"timestamp":1603009800,"contributions":2}]`,
		},
		{
			"different author is not counted for target user",
			3, 3, 0, `[]`,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			user := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: tc.userID})

			var doer *user_model.User
			if tc.doerID != 0 {
				doer = unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: tc.doerID})
			}

			heatmap, err := activities_model.GetUserHeatmapDataByUser(t.Context(), user, doer)
			require.NoError(t, err)
			assert.Equal(t, tc.CountResult, countHeatmapContributions(heatmap), "testcase '%s'", tc.desc)

			// Test JSON rendering
			jsonData, err := json.Marshal(heatmap)
			require.NoError(t, err)
			assert.JSONEq(t, tc.JSONResult, string(jsonData))
		})
	}
}

func TestGetUserHeatmapDataByOrgTeam(t *testing.T) {
	require.NoError(t, unittest.PrepareTestDatabase())
	require.NoError(t, db.TruncateBeans(t.Context(), &activities_model.HeatmapContribution{}))
	require.NoError(t, user_model.SetIncludePrivateContributions(t.Context(), 3, false))

	timeutil.MockSet(time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC))
	defer timeutil.MockUnset()

	insertHeatmapContribution(t, 2, 32, "org-team-public", 1603009800)
	insertHeatmapContribution(t, 2, 3, "org-team-private-hidden", 1603010700)
	insertHeatmapContribution(t, 2, 1, "non-org-repo-ignored", 1603011600)

	org := unittest.AssertExistsAndLoadBean(t, &organization.Organization{ID: 3})
	team := unittest.AssertExistsAndLoadBean(t, &organization.Team{ID: 7})
	doer := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: 2})

	heatmap, err := activities_model.GetUserHeatmapDataByOrgTeam(t.Context(), org, team, doer)
	require.NoError(t, err)
	assert.Equal(t, 1, countHeatmapContributions(heatmap))

	jsonData, err := json.Marshal(heatmap)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"timestamp":1603009800,"contributions":1}]`, string(jsonData))
}

func TestUserHeatmapPrivateContributionsOptIn(t *testing.T) {
	require.NoError(t, unittest.PrepareTestDatabase())
	require.NoError(t, db.TruncateBeans(t.Context(), &activities_model.HeatmapContribution{}))
	require.NoError(t, user_model.SetIncludePrivateContributions(t.Context(), 16, false))

	timeutil.MockSet(time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC))
	defer timeutil.MockUnset()

	insertHeatmapContribution(t, 16, 21, "user16-public", 1603009800)
	insertHeatmapContribution(t, 16, 22, "user16-private-one", 1603009850)
	insertHeatmapContribution(t, 16, 22, "user16-private-two", 1603010700)

	target := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: 16})
	admin := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: 1})
	authenticated := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: 3})
	collaborator := unittest.AssertExistsAndLoadBean(t, &user_model.User{ID: 15})

	for _, doer := range []*user_model.User{nil, target, admin, authenticated, collaborator} {
		heatmap, err := activities_model.GetUserHeatmapDataByUser(t.Context(), target, doer)
		require.NoError(t, err)
		assert.Equal(t, 1, countHeatmapContributions(heatmap), "private contributions should be hidden by default from %s", heatmapDoerName(doer))
	}

	require.NoError(t, user_model.SetIncludePrivateContributions(t.Context(), 16, true))
	heatmap, err := activities_model.GetUserHeatmapDataByUser(t.Context(), target, nil)
	require.NoError(t, err)
	jsonData, err := json.Marshal(heatmap)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"timestamp":1603009800,"contributions":2},{"timestamp":1603010700,"contributions":1}]`, string(jsonData))

	target.KeepActivityPrivate = true
	_, err = db.GetEngine(t.Context()).ID(target.ID).Cols("keep_activity_private").Update(target)
	require.NoError(t, err)

	heatmap, err = activities_model.GetUserHeatmapDataByUser(t.Context(), target, nil)
	require.NoError(t, err)
	assert.Empty(t, heatmap)

	heatmap, err = activities_model.GetUserHeatmapDataByUser(t.Context(), target, authenticated)
	require.NoError(t, err)
	assert.Empty(t, heatmap)

	heatmap, err = activities_model.GetUserHeatmapDataByUser(t.Context(), target, target)
	require.NoError(t, err)
	assert.Equal(t, 3, countHeatmapContributions(heatmap))

	heatmap, err = activities_model.GetUserHeatmapDataByUser(t.Context(), target, admin)
	require.NoError(t, err)
	assert.Equal(t, 3, countHeatmapContributions(heatmap))
}

func insertHeatmapContribution(t *testing.T, userID, repoID int64, commitSHA string, authorUnix timeutil.TimeStamp) {
	t.Helper()
	require.NoError(t, activities_model.UpsertHeatmapContribution(t.Context(), &activities_model.HeatmapContribution{
		UserID:      userID,
		RepoID:      repoID,
		CommitSHA:   fmt.Sprintf("%040x", sha1.Sum([]byte(commitSHA))),
		AuthorEmail: fmt.Sprintf("user%d@example.com", userID),
		AuthorUnix:  authorUnix,
	}))
}

func countHeatmapContributions(heatmap []*activities_model.UserHeatmapData) int {
	var contributions int
	for _, hm := range heatmap {
		contributions += int(hm.Contributions)
	}
	return contributions
}

func heatmapDoerName(doer *user_model.User) string {
	if doer == nil {
		return "anonymous"
	}
	return doer.Name
}
