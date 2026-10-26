import assert from 'node:assert/strict';
import test from 'node:test';
import { ApiError } from '../http/errors.ts';
import { validateHierarchy } from './hierarchy.ts';

test('team hierarchy accepts multiple roots and nested collaborators', () => {
  validateHierarchy([]);
  validateHierarchy([
    { id: 'lead', parentId: null },
    { id: 'developer', parentId: 'lead' },
    { id: 'tester', parentId: 'developer' },
    { id: 'designer', parentId: null },
  ]);
});

test('team hierarchy rejects duplicate members and supervisors from other teams', () => {
  for (const members of [
    [{ id: 'one', parentId: null }, { id: 'one', parentId: null }],
    [{ id: 'one', parentId: 'outsider' }],
  ]) {
    assert.throws(() => validateHierarchy(members), (error: unknown) =>
      error instanceof ApiError && error.code === 'INVALID_TEAM_HIERARCHY');
  }
});

test('team hierarchy rejects self references and indirect cycles', () => {
  for (const members of [
    [{ id: 'one', parentId: 'one' }],
    [{ id: 'one', parentId: 'two' }, { id: 'two', parentId: 'one' }],
    [
      { id: 'one', parentId: 'two' },
      { id: 'two', parentId: 'three' },
      { id: 'three', parentId: 'one' },
    ],
  ]) {
    assert.throws(() => validateHierarchy(members), (error: unknown) =>
      error instanceof ApiError && error.code === 'TEAM_HIERARCHY_CYCLE');
  }
});
